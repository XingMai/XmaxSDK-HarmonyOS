#include "file_frame_source.h"
#include "file_video_surface.h"

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstring>
#include <deque>
#include <fcntl.h>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <sys/stat.h>
#include <thread>
#include <unistd.h>
#include <vector>

#include "multimedia/player_framework/native_avbuffer.h"
#include "multimedia/player_framework/native_avcodec_audiocodec.h"
#include "multimedia/player_framework/native_avcodec_videodecoder.h"
#include "multimedia/player_framework/native_avdemuxer.h"
#include "multimedia/player_framework/native_avformat.h"
#include "multimedia/player_framework/native_avsource.h"
#include "native_buffer/buffer_common.h"

namespace {
using Clock = std::chrono::steady_clock;
using Format = std::unique_ptr<OH_AVFormat, decltype(&OH_AVFormat_Destroy)>;

void Check(OH_AVErrCode result, const char *message) {
  if (result != AV_ERR_OK) throw std::runtime_error(std::string(message) + ": " + std::to_string(result));
}

struct Frame {
  bool video = false;
  int width = 0, height = 0, sampleRate = 0, channels = 0;
  int64_t timestampUs = 0;
  std::vector<uint8_t> data;
  std::string error;
};

/** Owns the system demuxer and decoders; all blocking operations run off the ArkTS thread. */
class FileSource : public std::enable_shared_from_this<FileSource> {
public:
  struct Buffer { uint32_t index; OH_AVBuffer *value; };
  struct Track {
    FileSource *owner;
    bool video;
    uint32_t id;
    OH_AVCodec *codec = nullptr;
    std::deque<Buffer> inputs, outputs;
    std::unique_ptr<Frame> pending;
    bool inputEnded = false, ended = false;
    bool hdrVivid = false, surfacePending = false;
    int64_t surfacePts = 0;
    std::unique_ptr<FileVideoSurface> surface;
    int width = 0, height = 0, rotation = 0, sampleRate = 0, channels = 0;
    Track(FileSource *owner, bool video, uint32_t id) : owner(owner), video(video), id(id) {}
  };

  explicit FileSource(napi_threadsafe_function callback) : callback_(callback) {}
  ~FileSource() { Stop(); Close(); }

  void Open(int inputFd, int64_t length) {
    fd_ = dup(inputFd);
    struct stat info{};
    if (fd_ < 0 || fstat(fd_, &info) != 0 || info.st_size <= 0) throw std::runtime_error("Cannot open external video");
    length_ = std::min<int64_t>(length, info.st_size);
    OpenSource();

    Format format(OH_AVSource_GetSourceFormat(source_), OH_AVFormat_Destroy);
    int32_t count = 0;
    if (!format || !OH_AVFormat_GetIntValue(format.get(), OH_MD_KEY_TRACK_COUNT, &count))
      throw std::runtime_error("Cannot read external tracks");

    for (int i = 0; i < count; i++) {
      Format track(OH_AVSource_GetTrackFormat(source_, i), OH_AVFormat_Destroy);
      int32_t type = -1;
      if (!track || !OH_AVFormat_GetIntValue(track.get(), OH_MD_KEY_TRACK_TYPE, &type)) continue;
      if (type == MEDIA_TYPE_VID && !video_) video_ = MakeTrack(i, true, track.get());
      if (type == MEDIA_TYPE_AUD && !audio_) audio_ = MakeTrack(i, false, track.get());
    }
    if (!video_) throw std::runtime_error("The selected file has no video");
    width = video_->rotation % 180 ? video_->height : video_->width;
    height = video_->rotation % 180 ? video_->width : video_->height;
    hasAudio = audio_ != nullptr;
  }

  void Start() {
    if (started_.exchange(true)) return;
    auto self = shared_from_this();
    worker_ = std::thread([self] { self->Run(); });
  }

  void RequestStop() {
    stopping_ = true;
    changed_.notify_all();
  }

  void Stop() {
    std::lock_guard<std::mutex> stopLock(stopMutex_);
    RequestStop();
    if (worker_.joinable()) worker_.join();
    if (!started_) {
      Close();
      FinishCallback();
    }
  }

  int width = 0, height = 0;
  bool hasAudio = false;

private:
  int fd_ = -1;
  int64_t length_ = 0;
  OH_AVSource *source_ = nullptr;
  OH_AVDemuxer *demuxer_ = nullptr;
  std::unique_ptr<Track> video_, audio_;
  napi_threadsafe_function callback_;
  std::thread worker_;
  std::atomic<bool> stopping_{false}, started_{false};
  std::atomic<bool> callbackReleased_{false};
  std::mutex mutex_;
  std::mutex stopMutex_;
  std::condition_variable changed_;
  std::string error_;
  int64_t anchorUs_ = 0;
  int64_t firstMediaUs_ = -1;
  int64_t lastOutputUs_ = -1;
  bool timelineStarted_ = false;

  void FinishCallback() {
    if (!callbackReleased_.exchange(true)) napi_release_threadsafe_function(callback_, napi_tsfn_release);
  }

  std::unique_ptr<Track> MakeTrack(uint32_t id, bool video, OH_AVFormat *format) {
    auto track = std::make_unique<Track>(this, video, id);
    OH_AVFormat_GetIntValue(format, OH_MD_KEY_WIDTH, &track->width);
    OH_AVFormat_GetIntValue(format, OH_MD_KEY_HEIGHT, &track->height);
    OH_AVFormat_GetIntValue(format, OH_MD_KEY_ROTATION, &track->rotation);
    track->rotation = (track->rotation % 360 + 360) % 360;
    if (video && track->rotation % 90 != 0) throw std::runtime_error("Unsupported external file rotation");
    OH_AVFormat_GetIntValue(format, OH_MD_KEY_AUD_SAMPLE_RATE, &track->sampleRate);
    OH_AVFormat_GetIntValue(format, OH_MD_KEY_AUD_CHANNEL_COUNT, &track->channels);
    int32_t hdrVivid = 0;
    track->hdrVivid = video && OH_AVFormat_GetIntValue(format, OH_MD_KEY_VIDEO_IS_HDR_VIVID, &hdrVivid) &&
        hdrVivid == 1;
    if (video && (track->width < 2 || track->height < 2 || track->width % 2 || track->height % 2 ||
        static_cast<int64_t>(track->width) * track->height > 16777216))
      throw std::runtime_error("Unsupported external file dimensions");
    return track;
  }

  static void Error(OH_AVCodec *, int32_t code, void *data) {
    auto &owner = *static_cast<Track *>(data)->owner;
    std::lock_guard<std::mutex> lock(owner.mutex_);
    owner.error_ = "External file decoder failed: " + std::to_string(code);
    owner.changed_.notify_one();
  }
  static void FormatChanged(OH_AVCodec *, OH_AVFormat *, void *) {}
  static void Input(OH_AVCodec *, uint32_t index, OH_AVBuffer *buffer, void *data) {
    auto &track = *static_cast<Track *>(data);
    std::lock_guard<std::mutex> lock(track.owner->mutex_);
    track.inputs.push_back({index, buffer});
    track.owner->changed_.notify_one();
  }
  static void Output(OH_AVCodec *, uint32_t index, OH_AVBuffer *buffer, void *data) {
    auto &track = *static_cast<Track *>(data);
    std::lock_guard<std::mutex> lock(track.owner->mutex_);
    track.outputs.push_back({index, buffer});
    track.owner->changed_.notify_one();
  }
  bool Pop(std::deque<Buffer> &queue, Buffer &buffer) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (queue.empty()) return false;
    buffer = queue.front();
    queue.pop_front();
    return true;
  }

  void Prepare(Track &track) {
    Format format(OH_AVSource_GetTrackFormat(source_, track.id), OH_AVFormat_Destroy);
    const char *mime = nullptr;
    if (!format || !OH_AVFormat_GetStringValue(format.get(), OH_MD_KEY_CODEC_MIME, &mime))
      throw std::runtime_error("Missing external codec format");
    track.codec = track.video ? OH_VideoDecoder_CreateByMime(mime) : OH_AudioCodec_CreateByMime(mime, false);
    if (!track.codec) throw std::runtime_error("External file decoder is unavailable");
    const OH_AVCodecCallback callbacks{Error, FormatChanged, Input, Output};
    if (track.video) {
      OH_AVFormat_SetIntValue(format.get(), OH_MD_KEY_PIXEL_FORMAT, AV_PIXEL_FORMAT_NV12);
      if (track.hdrVivid) {
        OH_AVFormat_SetIntValue(format.get(), OH_MD_KEY_VIDEO_DECODER_OUTPUT_COLOR_SPACE, OH_COLORSPACE_BT709_LIMIT);
        track.surface = std::make_unique<FileVideoSurface>(track.width, track.height, stopping_);
      }
      Check(OH_VideoDecoder_RegisterCallback(track.codec, callbacks, &track), "Observe external video");
      Check(OH_VideoDecoder_Configure(track.codec, format.get()), "Configure external video");
      if (track.surface) {
        Check(OH_VideoDecoder_SetSurface(track.codec, track.surface->InputWindow()), "Bind external HDR Surface");
      }
      Check(OH_VideoDecoder_Prepare(track.codec), "Prepare external video");
      Check(OH_VideoDecoder_Start(track.codec), "Start external video");
      if (track.surface) track.surface->Start();
    } else {
      OH_AVFormat_SetIntValue(format.get(), OH_MD_KEY_AUDIO_SAMPLE_FORMAT, SAMPLE_S16LE);
      Check(OH_AudioCodec_RegisterCallback(track.codec, callbacks, &track), "Observe external audio");
      Check(OH_AudioCodec_Configure(track.codec, format.get()), "Configure external audio");
      Check(OH_AudioCodec_Prepare(track.codec), "Prepare external audio");
      Check(OH_AudioCodec_Start(track.codec), "Start external audio");
    }
    Check(OH_AVDemuxer_SelectTrackByID(demuxer_, track.id), "Select external track");
  }

  void Feed(Track &track) {
    Buffer input{};
    while (!stopping_ && !track.inputEnded && Pop(track.inputs, input)) {
      Check(OH_AVDemuxer_ReadSampleBuffer(demuxer_, track.id, input.value), "Read external sample");
      OH_AVCodecBufferAttr attr{};
      Check(OH_AVBuffer_GetBufferAttr(input.value, &attr), "Read external attributes");
      track.inputEnded = (attr.flags & AVCODEC_BUFFER_FLAGS_EOS) != 0;
      Check(track.video ? OH_VideoDecoder_PushInputBuffer(track.codec, input.index) :
          OH_AudioCodec_PushInputBuffer(track.codec, input.index), "Submit external sample");
    }
  }

  /** Copies upright NV12 from either mapped Surface planes or decoder byte buffers. */
  std::unique_ptr<Frame> CopyVideoFrame(Track &track, const uint8_t *yData, int yStride,
      const uint8_t *uvData, int uvStride, int64_t pts) {
    auto frame = std::make_unique<Frame>();
    frame->video = true;
    frame->timestampUs = pts;
    if (firstMediaUs_ < 0 || !timelineStarted_) {
      firstMediaUs_ = firstMediaUs_ < 0 ? pts : std::min(firstMediaUs_, pts);
    }

    frame->width = track.rotation % 180 ? track.height : track.width;
    frame->height = track.rotation % 180 ? track.width : track.height;
    const size_t ySize = static_cast<size_t>(frame->width) * frame->height;
    frame->data.resize(ySize * 3 / 2);
    for (int plane = 0; plane < 2; plane++) {
      const int step = plane == 0 ? 1 : 2;
      const int w = track.width / step, h = track.height / step;
      const int outW = frame->width / step;
      const uint8_t *data = plane ? uvData : yData;
      const int stride = plane ? uvStride : yStride;
      for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) {
        int ox = x, oy = y;
        if (track.rotation == 90) { ox = h - y - 1; oy = x; }
        else if (track.rotation == 180) { ox = w - x - 1; oy = h - y - 1; }
        else if (track.rotation == 270) { ox = y; oy = w - x - 1; }
        std::memcpy(frame->data.data() + (plane ? ySize : 0) + (oy * outW + ox) * step,
            data + y * stride + x * step, step);
      }
    }
    return frame;
  }

  std::unique_ptr<Frame> CopyFrame(Track &track, OH_AVBuffer *buffer, OH_AVCodecBufferAttr attr) {
    const uint8_t *data = OH_AVBuffer_GetAddr(buffer);
    if (!data || attr.offset < 0 || attr.size < 0 ||
        static_cast<int64_t>(attr.offset) + attr.size > OH_AVBuffer_GetCapacity(buffer))
      throw std::runtime_error("Invalid external decoded buffer");

    Format format(track.video ? OH_VideoDecoder_GetOutputDescription(track.codec) :
        OH_AudioCodec_GetOutputDescription(track.codec), OH_AVFormat_Destroy);
    if (track.video) {
      int32_t stride = 0, slice = 0, pixelFormat = 0;
      if (!format || !OH_AVFormat_GetIntValue(format.get(), OH_MD_KEY_VIDEO_STRIDE, &stride) ||
          !OH_AVFormat_GetIntValue(format.get(), OH_MD_KEY_VIDEO_SLICE_HEIGHT, &slice) ||
          !OH_AVFormat_GetIntValue(format.get(), OH_MD_KEY_PIXEL_FORMAT, &pixelFormat) ||
          pixelFormat != AV_PIXEL_FORMAT_NV12 || stride < track.width || slice < track.height)
        throw std::runtime_error("External file decoder did not output SDR NV12");
      const size_t chroma = static_cast<size_t>(stride) * slice;
      if (chroma + static_cast<size_t>(track.height / 2 - 1) * stride + track.width >
          static_cast<size_t>(OH_AVBuffer_GetCapacity(buffer) - attr.offset))
        throw std::runtime_error("Invalid external NV12 planes");
      return CopyVideoFrame(track, data + attr.offset, stride, data + attr.offset + chroma, stride, attr.pts);
    }

    int32_t sampleFormat = SAMPLE_S16LE;
    if (!format || (OH_AVFormat_GetIntValue(format.get(), OH_MD_KEY_AUDIO_SAMPLE_FORMAT, &sampleFormat) &&
        sampleFormat != SAMPLE_S16LE)) throw std::runtime_error("External audio decoder did not output PCM16");
    auto frame = std::make_unique<Frame>();
    frame->timestampUs = attr.pts;
    if (firstMediaUs_ < 0 || !timelineStarted_) {
      firstMediaUs_ = firstMediaUs_ < 0 ? attr.pts : std::min(firstMediaUs_, attr.pts);
    }
    frame->sampleRate = track.sampleRate;
    frame->channels = track.channels;
    OH_AVFormat_GetIntValue(format.get(), OH_MD_KEY_AUD_SAMPLE_RATE, &frame->sampleRate);
    OH_AVFormat_GetIntValue(format.get(), OH_MD_KEY_AUD_CHANNEL_COUNT, &frame->channels);
    frame->data.assign(data + attr.offset, data + attr.offset + attr.size);
    return frame;
  }

  void Drain(Track &track) {
    if (stopping_ || track.pending) return;
    if (track.surface) {
      track.surface->CheckError();
      if (track.surfacePending) {
        if (track.surface->Read([&](const uint8_t *y, int yStride, const uint8_t *uv, int uvStride) {
          track.pending = CopyVideoFrame(track, y, yStride, uv, uvStride, track.surfacePts);
        })) track.surfacePending = false;
        return;
      }
    }

    Buffer output{};
    if (Pop(track.outputs, output)) {
      try {
        OH_AVCodecBufferAttr attr{};
        Check(OH_AVBuffer_GetBufferAttr(output.value, &attr), "Read external decoded attributes");
        track.ended = (attr.flags & AVCODEC_BUFFER_FLAGS_EOS) != 0;
        if (track.surface && !track.ended) {
          // Keep a single Surface frame in flight; consume it before reading the next frame or EOS.
          track.surfacePts = attr.pts;
          Check(OH_VideoDecoder_RenderOutputBuffer(track.codec, output.index), "Render external HDR frame");
          track.surfacePending = true;
          return;
        } else if (!track.surface && attr.size > 0) {
          track.pending = CopyFrame(track, output.value, attr);
        }
      } catch (...) {
        Release(track, output.index);
        throw;
      }
      Release(track, output.index);
    }
  }

  /** Interleaves decoded tracks by presentation time without queuing a whole file in memory. */
  void DeliverNext() {
    if ((!video_->pending && !video_->ended) || (audio_ && !audio_->pending && !audio_->ended)) return;
    Track *next = video_->pending ? video_.get() : nullptr;
    if (audio_ && audio_->pending && (!next || audio_->pending->timestampUs < next->pending->timestampUs))
      next = audio_.get();
    if (!next) return;

    timelineStarted_ = true;
    auto frame = std::move(next->pending);
    frame->timestampUs += anchorUs_ - firstMediaUs_;
    const auto due = Clock::time_point(std::chrono::microseconds(frame->timestampUs));
    std::unique_lock<std::mutex> lock(mutex_);
    changed_.wait_until(lock, due, [this] { return stopping_.load() || !error_.empty(); });
    if (!error_.empty()) throw std::runtime_error(error_);
    lock.unlock();
    if (!stopping_) {
      lastOutputUs_ = std::max(lastOutputUs_, frame->timestampUs);
      Frame *event = frame.release();
      if (napi_call_threadsafe_function(callback_, event, napi_tsfn_blocking) != napi_ok) delete event;
    }
  }

  void Release(Track &track, uint32_t index) {
    Check(track.video ? OH_VideoDecoder_FreeOutputBuffer(track.codec, index) :
        OH_AudioCodec_FreeOutputBuffer(track.codec, index), "Release external decoded frame");
  }

  void CloseTrack(Track &track) {
    if (track.codec) {
      if (track.video) { OH_VideoDecoder_Stop(track.codec); OH_VideoDecoder_Destroy(track.codec); }
      else { OH_AudioCodec_Stop(track.codec); OH_AudioCodec_Destroy(track.codec); }
      track.codec = nullptr;
    }
    track.surface.reset();
    track.surfacePending = false;
    std::lock_guard<std::mutex> lock(mutex_);
    track.inputs.clear();
    track.outputs.clear();
    track.pending.reset();
    track.ended = false;
    track.inputEnded = false;
  }

  /** Creates a fresh media source; destroying its demuxer also releases the shared parsing state. */
  void OpenSource() {
    source_ = OH_AVSource_CreateWithFD(fd_, 0, length_);
    if (!source_) throw std::runtime_error("Cannot read external video");
  }

  /** Releases one playback cycle while retaining the owned file descriptor for the next cycle. */
  void CloseCycle() {
    if (video_) CloseTrack(*video_);
    if (audio_) CloseTrack(*audio_);
    if (demuxer_) { OH_AVDemuxer_Destroy(demuxer_); demuxer_ = nullptr; }
    if (source_) { OH_AVSource_Destroy(source_); source_ = nullptr; }
  }

  void Close() {
    CloseCycle();
    if (fd_ >= 0) { close(fd_); fd_ = -1; }
  }

  void Run() {
    try {
      while (!stopping_) {
        anchorUs_ = std::max<int64_t>(lastOutputUs_ + 10000,
            std::chrono::duration_cast<std::chrono::microseconds>(Clock::now().time_since_epoch()).count());
        firstMediaUs_ = -1;
        timelineStarted_ = false;
        if (!source_) OpenSource();

        demuxer_ = OH_AVDemuxer_CreateWithSource(source_);
        if (!demuxer_) throw std::runtime_error("Cannot create external file demuxer");
        Prepare(*video_);
        if (audio_) Prepare(*audio_);
        Check(OH_AVDemuxer_SeekToTime(demuxer_, 0, SEEK_MODE_CLOSEST_SYNC), "Rewind external video");

        while (!stopping_ && (!video_->ended || video_->pending ||
            (audio_ && (!audio_->ended || audio_->pending)))) {
          {
            std::unique_lock<std::mutex> lock(mutex_);
            changed_.wait_for(lock, std::chrono::milliseconds(2));
            if (!error_.empty()) throw std::runtime_error(error_);
          }
          Feed(*video_);
          if (audio_) Feed(*audio_);
          Drain(*video_);
          if (audio_) Drain(*audio_);
          DeliverNext();
        }
        CloseCycle();
      }
    } catch (const std::exception &error) {
      auto *event = new Frame;
      event->error = error.what();
      if (napi_call_threadsafe_function(callback_, event, napi_tsfn_blocking) != napi_ok) delete event;
    }
    Close();
    FinishCallback();
  }
};

void Require(napi_status result) {
  if (result != napi_ok) throw std::runtime_error("Invalid external file source argument");
}
napi_value Number(napi_env env, double value) {
  napi_value result;
  napi_create_double(env, value, &result);
  return result;
}
void Set(napi_env env, napi_value object, const char *key, napi_value value) {
  napi_set_named_property(env, object, key, value);
}
void Deliver(napi_env env, napi_value callback, void *, void *value) {
  std::unique_ptr<Frame> frame(static_cast<Frame *>(value));
  if (!env || !callback) return;
  napi_value result, ignored, receiver;
  napi_create_object(env, &result);
  if (!frame->error.empty()) {
    napi_value text;
    napi_create_string_utf8(env, frame->error.c_str(), frame->error.size(), &text);
    Set(env, result, "error", text);
  } else {
    napi_value video, bytes;
    void *storage = nullptr;
    napi_get_boolean(env, frame->video, &video);
    if (napi_create_arraybuffer(env, frame->data.size(), &storage, &bytes) != napi_ok || !storage) return;
    std::memcpy(storage, frame->data.data(), frame->data.size());
    Set(env, result, "video", video);
    Set(env, result, "data", bytes);
    Set(env, result, "width", Number(env, frame->width));
    Set(env, result, "height", Number(env, frame->height));
    Set(env, result, "sampleRate", Number(env, frame->sampleRate));
    Set(env, result, "channels", Number(env, frame->channels));
    Set(env, result, "timestampUs", Number(env, frame->timestampUs));
  }
  napi_get_undefined(env, &receiver);
  napi_call_function(env, receiver, callback, 1, &result, &ignored);
}
using Source = std::shared_ptr<FileSource>;
struct Work {
  Source source;
  std::string error;
  int fd = -1;
  int64_t length = 0;
  napi_async_work work = nullptr;
  napi_deferred deferred = nullptr;
  napi_threadsafe_function callback = nullptr;
  bool opening = false;
};
void Finalize(napi_env, void *value, void *) {
  std::unique_ptr<Source> source(static_cast<Source *>(value));
  (*source)->RequestStop();
  std::thread([source = *source] { source->Stop(); }).detach();
}
Source Get(napi_env env, napi_callback_info info) {
  napi_value receiver;
  Require(napi_get_cb_info(env, info, nullptr, nullptr, &receiver, nullptr));
  Source *source = nullptr;
  Require(napi_unwrap(env, receiver, reinterpret_cast<void **>(&source)));
  if (!source) throw std::runtime_error("External file source is closed");
  return *source;
}
napi_value Start(napi_env env, napi_callback_info info) {
  try { Get(env, info)->Start(); }
  catch (const std::exception &error) { napi_throw_error(env, nullptr, error.what()); }
  return nullptr;
}
void Execute(napi_env, void *value) {
  auto &work = *static_cast<Work *>(value);
  try {
    if (work.opening) work.source->Open(work.fd, work.length);
    else work.source->Stop();
  } catch (const std::exception &error) {
    work.error = error.what();
    work.source->Stop();
  }
}
napi_value Release(napi_env env, napi_callback_info info);
void Complete(napi_env env, napi_status status, void *value) {
  std::unique_ptr<Work> work(static_cast<Work *>(value));
  napi_value result;
  if (status != napi_ok || !work->error.empty()) {
    napi_value message;
    const std::string error = work->error.empty() ? "External file operation cancelled" : work->error;
    napi_create_string_utf8(env, error.c_str(), error.size(), &message);
    napi_create_error(env, nullptr, message, &result);
    napi_reject_deferred(env, work->deferred, result);
  } else if (work->opening) {
    napi_create_object(env, &result);
    napi_wrap(env, result, new Source(work->source), Finalize, nullptr, nullptr);
    const napi_property_descriptor methods[] = {
        {"start", nullptr, Start, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"release", nullptr, Release, nullptr, nullptr, nullptr, napi_default, nullptr}};
    napi_define_properties(env, result, 2, methods);
    Set(env, result, "width", Number(env, work->source->width));
    Set(env, result, "height", Number(env, work->source->height));
    napi_value audio;
    napi_get_boolean(env, work->source->hasAudio, &audio);
    Set(env, result, "hasAudio", audio);
    napi_resolve_deferred(env, work->deferred, result);
  } else {
    napi_get_undefined(env, &result);
    napi_resolve_deferred(env, work->deferred, result);
  }
  napi_delete_async_work(env, work->work);
}
napi_value Queue(napi_env env, std::unique_ptr<Work> work) {
  napi_value promise, name;
  Require(napi_create_promise(env, &work->deferred, &promise));
  napi_create_string_utf8(env, "XLab file source", NAPI_AUTO_LENGTH, &name);
  Require(napi_create_async_work(env, nullptr, name, Execute, Complete, work.get(), &work->work));
  Require(napi_queue_async_work(env, work->work));
  work.release();
  return promise;
}
napi_value Release(napi_env env, napi_callback_info info) {
  try {
    auto work = std::make_unique<Work>();
    work->source = Get(env, info);
    work->source->RequestStop();
    return Queue(env, std::move(work));
  } catch (const std::exception &error) { napi_throw_error(env, nullptr, error.what()); return nullptr; }
}
napi_value Create(napi_env env, napi_callback_info info) {
  try {
    size_t count = 3;
    napi_value args[3], name;
    Require(napi_get_cb_info(env, info, &count, args, nullptr, nullptr));
    if (count != 3) throw std::runtime_error("External file source requires descriptor, length, and callback");
    auto work = std::make_unique<Work>();
    work->opening = true;
    Require(napi_get_value_int32(env, args[0], &work->fd));
    Require(napi_get_value_int64(env, args[1], &work->length));
    if (work->fd < 0 || work->length <= 0) throw std::runtime_error("Invalid external file descriptor");
    napi_create_string_utf8(env, "XLab decoded file frame", NAPI_AUTO_LENGTH, &name);
    Require(napi_create_threadsafe_function(env, args[2], nullptr, name, 4, 1, nullptr, nullptr, nullptr,
        Deliver, &work->callback));
    work->source = std::make_shared<FileSource>(work->callback);
    return Queue(env, std::move(work));
  } catch (const std::exception &error) { napi_throw_error(env, nullptr, error.what()); return nullptr; }
}
} // namespace

void DefineFileFrameSource(napi_env env, napi_value exports) {
  napi_property_descriptor method = {"createFileSource", nullptr, Create,
      nullptr, nullptr, nullptr, napi_default, nullptr};
  napi_define_properties(env, exports, 1, &method);
}
