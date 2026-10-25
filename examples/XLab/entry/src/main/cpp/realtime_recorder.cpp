#include "realtime_recorder.h"

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <cmath>
#include <cstring>
#include <deque>
#include <fcntl.h>
#include <mutex>
#include <stdexcept>
#include <sys/stat.h>
#include <thread>
#include <unistd.h>

#include "multimedia/player_framework/native_avbuffer.h"
#include "multimedia/player_framework/native_avcodec_audiocodec.h"
#include "multimedia/player_framework/native_avcodec_videoencoder.h"
#include "multimedia/player_framework/native_avdemuxer.h"
#include "multimedia/player_framework/native_avformat.h"
#include "multimedia/player_framework/native_avmuxer.h"
#include "multimedia/player_framework/native_avsource.h"

namespace xlab {
namespace {

using Clock = std::chrono::steady_clock;
using Format = std::unique_ptr<OH_AVFormat, decltype(&OH_AVFormat_Destroy)>;

void Check(OH_AVErrCode code, const char *operation) {
  if (code != AV_ERR_OK) {
    throw std::runtime_error(std::string(operation) + ": " + std::to_string(code));
  }
}

/** Owns a single-track MP4 reader used only during final remuxing. */
struct TrackReader {
  int fd = -1;
  OH_AVSource *source = nullptr;
  OH_AVDemuxer *demuxer = nullptr;
  OH_AVBuffer *buffer = nullptr;
  int32_t outputTrack = -1;
  int64_t offsetUs = 0;
  OH_AVCodecBufferAttr attr{};
  bool ended = false;

  ~TrackReader() {
    if (buffer) OH_AVBuffer_Destroy(buffer);
    if (demuxer) OH_AVDemuxer_Destroy(demuxer);
    if (source) OH_AVSource_Destroy(source);
    if (fd >= 0) close(fd);
  }

  void Open(const std::string &path, OH_AVMuxer *muxer, int32_t capacity) {
    fd = open(path.c_str(), O_RDONLY);
    struct stat info{};
    if (fd < 0 || fstat(fd, &info) != 0) throw std::runtime_error("Cannot open encoded track");
    source = OH_AVSource_CreateWithFD(fd, 0, info.st_size);
    if (!source) throw std::runtime_error("Cannot read encoded track");
    Format format(OH_AVSource_GetTrackFormat(source, 0), OH_AVFormat_Destroy);
    if (!format) throw std::runtime_error("Cannot read track format");
    Check(OH_AVMuxer_AddTrack(muxer, &outputTrack, format.get()), "Add final track");

    demuxer = OH_AVDemuxer_CreateWithSource(source);
    buffer = OH_AVBuffer_Create(capacity);
    if (!demuxer || !buffer) throw std::runtime_error("Cannot create track reader");
    Check(OH_AVDemuxer_SelectTrackByID(demuxer, 0), "Select encoded track");
    Read();
  }

  void Read() {
    Check(OH_AVDemuxer_ReadSampleBuffer(demuxer, 0, buffer), "Read encoded sample");
    Check(OH_AVBuffer_GetBufferAttr(buffer, &attr), "Read sample attributes");
    ended = (attr.flags & AVCODEC_BUFFER_FLAGS_EOS) != 0;
    attr.pts += offsetUs;
    Check(OH_AVBuffer_SetBufferAttr(buffer, &attr), "Set final timestamp");
  }
};

} // namespace

/** All codec and muxer work belongs to one worker; codec callbacks only enqueue buffer handles. */
class RealtimeRecorder::State {
public:
  struct Buffer {
    uint32_t index;
    OH_AVBuffer *value;
  };

  struct Track {
    State *owner;
    bool video;
    OH_AVCodec *codec = nullptr;
    OH_AVMuxer *muxer = nullptr;
    int fd = -1;
    int32_t muxerTrack = -1;
    bool started = false;
    bool inputEnded = false;
    bool outputEnded = false;
    int32_t width = 0, height = 0, rotation = 0, sampleRate = 0, channels = 0;
    int32_t stride = 0, sliceHeight = 0;
    int64_t originUs = 0, arrivalUs = 0, lastQueuedUs = -1, endUs = 0;
    int64_t lastQueuedEndUs = -1;
    size_t pendingBytes = 0;
    size_t packetOffset = 0;
    size_t written = 0;
    std::deque<Buffer> inputs, outputs;
    std::deque<RecordingPacket> pending;

    Track(State *state, bool isVideo) : owner(state), video(isVideo) {}
  };

  State(std::string path, std::function<void(std::string)> failure)
      : path_(std::move(path)), failure_(std::move(failure)), video_(this, true), audio_(this, false) {
    worker_ = std::thread([this] { Run(); });
  }

  ~State() {
    Stop(true);
    if (worker_.joinable()) worker_.join();
  }

  void Append(RecordingPacket packet) {
    packet.arrivalUs = std::chrono::duration_cast<std::chrono::microseconds>(Clock::now().time_since_epoch()).count();
    std::lock_guard<std::mutex> lock(mutex_);
    if (!error_.empty()) throw std::runtime_error(error_);
    if (stopping_) return;
    if (retainedPackets_ >= 256 || packet.data.size() > 32 * 1024 * 1024 - retainedBytes_) {
      throw std::runtime_error("Recording queue is full");
    }

    retainedBytes_ += packet.data.size();
    retainedPackets_++;
    incoming_.push_back(std::move(packet));
    changed_.notify_one();
  }

  std::string Finish(bool cancel) {
    Stop(cancel);
    if (worker_.joinable()) worker_.join();
    if (!cancel && !error_.empty()) throw std::runtime_error(error_);
    return path_;
  }

private:
  std::string path_;
  std::function<void(std::string)> failure_;
  std::mutex mutex_;
  std::condition_variable changed_;
  std::thread worker_;
  std::deque<RecordingPacket> incoming_;
  size_t retainedBytes_ = 0, retainedPackets_ = 0;
  bool stopping_ = false, cancelled_ = false;
  std::string error_;
  Clock::time_point deadline_;
  Track video_, audio_;

  void Stop(bool cancel) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!stopping_) deadline_ = Clock::now() + std::chrono::seconds(10);
    stopping_ = true;
    cancelled_ = cancelled_ || cancel;
    changed_.notify_one();
  }

  static void OnError(OH_AVCodec *, int32_t code, void *data) {
    auto &state = *static_cast<Track *>(data)->owner;
    std::lock_guard<std::mutex> lock(state.mutex_);
    if (state.error_.empty()) state.error_ = "Recording encoder failed: " + std::to_string(code);
    state.changed_.notify_one();
  }

  static void OnFormat(OH_AVCodec *, OH_AVFormat *, void *) {}

  static void OnInput(OH_AVCodec *, uint32_t index, OH_AVBuffer *buffer, void *data) {
    auto &track = *static_cast<Track *>(data);
    std::lock_guard<std::mutex> lock(track.owner->mutex_);
    track.inputs.push_back({index, buffer});
    track.owner->changed_.notify_one();
  }

  static void OnOutput(OH_AVCodec *, uint32_t index, OH_AVBuffer *buffer, void *data) {
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

  void Prepare(Track &track, const RecordingPacket &packet) {
    track.width = packet.width;
    track.height = packet.height;
    track.rotation = packet.rotation;
    track.sampleRate = packet.sampleRate;
    track.channels = packet.channels;
    track.originUs = packet.timestampUs;
    track.arrivalUs = packet.arrivalUs;
    track.codec = track.video ? OH_VideoEncoder_CreateByMime(OH_AVCODEC_MIMETYPE_VIDEO_AVC) :
        OH_AudioCodec_CreateByMime(OH_AVCODEC_MIMETYPE_AUDIO_AAC, true);
    if (!track.codec) throw std::runtime_error("Recording encoder is unavailable");

    const OH_AVCodecCallback callbacks{OnError, OnFormat, OnInput, OnOutput};
    Format format(OH_AVFormat_Create(), OH_AVFormat_Destroy);
    if (!format) throw std::runtime_error("Cannot create recording format");
    OH_AVFormat_SetStringValue(format.get(), OH_MD_KEY_CODEC_MIME,
        track.video ? OH_AVCODEC_MIMETYPE_VIDEO_AVC : OH_AVCODEC_MIMETYPE_AUDIO_AAC);
    if (track.video) {
      OH_AVFormat_SetIntValue(format.get(), OH_MD_KEY_WIDTH, track.width);
      OH_AVFormat_SetIntValue(format.get(), OH_MD_KEY_HEIGHT, track.height);
      OH_AVFormat_SetIntValue(format.get(), OH_MD_KEY_PIXEL_FORMAT, AV_PIXEL_FORMAT_NV12);
      OH_AVFormat_SetIntValue(format.get(), OH_MD_KEY_PROFILE, AVC_PROFILE_BASELINE);
      OH_AVFormat_SetDoubleValue(format.get(), OH_MD_KEY_FRAME_RATE, 30.0);
      OH_AVFormat_SetLongValue(format.get(), OH_MD_KEY_BITRATE,
          std::clamp<int64_t>(static_cast<int64_t>(track.width) * track.height * 4, 2000000, 12000000));
      OH_AVFormat_SetIntValue(format.get(), OH_MD_KEY_I_FRAME_INTERVAL, 2000);
      Check(OH_VideoEncoder_RegisterCallback(track.codec, callbacks, &track), "Observe video encoder");
      Check(OH_VideoEncoder_Configure(track.codec, format.get()), "Configure video encoder");
      Check(OH_VideoEncoder_Prepare(track.codec), "Prepare video encoder");
      Check(OH_VideoEncoder_Start(track.codec), "Start video encoder");
    } else {
      OH_AVFormat_SetIntValue(format.get(), OH_MD_KEY_AUD_SAMPLE_RATE, track.sampleRate);
      OH_AVFormat_SetIntValue(format.get(), OH_MD_KEY_AUD_CHANNEL_COUNT, track.channels);
      OH_AVFormat_SetIntValue(format.get(), OH_MD_KEY_AUDIO_SAMPLE_FORMAT, SAMPLE_S16LE);
      OH_AVFormat_SetIntValue(format.get(), OH_MD_KEY_PROFILE, AAC_PROFILE_LC);
      OH_AVFormat_SetLongValue(format.get(), OH_MD_KEY_BITRATE, 128000);
      OH_AVFormat_SetIntValue(format.get(), OH_MD_KEY_AAC_IS_ADTS, 0);
      Check(OH_AudioCodec_RegisterCallback(track.codec, callbacks, &track), "Observe audio encoder");
      Check(OH_AudioCodec_Configure(track.codec, format.get()), "Configure audio encoder");
      Check(OH_AudioCodec_Prepare(track.codec), "Prepare audio encoder");
      Check(OH_AudioCodec_Start(track.codec), "Start audio encoder");
    }
    track.started = true;
  }

  void Enqueue(RecordingPacket packet) {
    Track &track = packet.video ? video_ : audio_;
    if (!track.codec) {
      const Track &other = packet.video ? audio_ : video_;
      // Reject clearly different native clock origins; arrival time is not used to rewrite media PTS.
      if (other.codec && std::abs((packet.timestampUs - other.originUs) -
          (packet.arrivalUs - other.arrivalUs)) > 1000000) {
        throw std::runtime_error("Audio/video clocks do not match; synchronized recording is unavailable");
      }
      Prepare(track, packet);
    }
    if (track.width != packet.width || track.height != packet.height || track.rotation != packet.rotation ||
        track.sampleRate != packet.sampleRate || track.channels != packet.channels) {
      throw std::runtime_error("Recording format changed; start a new recording");
    }
    const int64_t relativeUs = packet.timestampUs - track.originUs;
    if (relativeUs < 0 || relativeUs <= track.lastQueuedUs) {
      throw std::runtime_error("Recording timestamp moved backwards");
    }
    if (!track.video) {
      if (track.lastQueuedEndUs >= 0 && std::abs(relativeUs - track.lastQueuedEndUs) > 2) {
        throw std::runtime_error("Recording audio timeline was interrupted");
      }
      track.lastQueuedEndUs = relativeUs + static_cast<int64_t>(std::llround(
          static_cast<double>(packet.data.size() / (2 * track.channels)) * 1000000 / track.sampleRate));
    }
    track.lastQueuedUs = relativeUs;
    track.pendingBytes += packet.data.size();
    track.pending.push_back(std::move(packet));
  }

  int32_t CopyVideo(Track &track, const RecordingPacket &packet, OH_AVBuffer *buffer) {
    if (track.stride == 0) {
      Format format(OH_VideoEncoder_GetInputDescription(track.codec), OH_AVFormat_Destroy);
      if (!format || !OH_AVFormat_GetIntValue(format.get(), OH_MD_KEY_VIDEO_STRIDE, &track.stride) ||
          !OH_AVFormat_GetIntValue(format.get(), OH_MD_KEY_VIDEO_SLICE_HEIGHT, &track.sliceHeight)) {
        throw std::runtime_error("Cannot read encoder input alignment");
      }
    }

    const int64_t size = static_cast<int64_t>(track.stride) * track.sliceHeight * 3 / 2;
    uint8_t *target = OH_AVBuffer_GetAddr(buffer);
    if (!target || track.stride < track.width || track.sliceHeight < track.height ||
        track.stride % 2 != 0 || track.sliceHeight % 2 != 0 || size > OH_AVBuffer_GetCapacity(buffer)) {
      throw std::runtime_error("Invalid encoder video buffer layout");
    }

    const size_t ySize = static_cast<size_t>(track.width) * track.height;
    const size_t paddedYSize = static_cast<size_t>(track.stride) * track.sliceHeight;
    std::memset(target, 16, paddedYSize);
    std::memset(target + paddedYSize, 128, paddedYSize / 2);
    for (int y = 0; y < track.height; y++) {
      std::memcpy(target + y * track.stride, packet.data.data() + y * track.width, track.width);
    }
    for (int y = 0; y < track.height / 2; y++) {
      for (int x = 0; x < track.width / 2; x++) {
        const size_t offset = static_cast<size_t>(y) * track.width / 2 + x;
        target[paddedYSize + y * track.stride + 2 * x] = packet.data[ySize + offset];
        target[paddedYSize + y * track.stride + 2 * x + 1] = packet.data[ySize + ySize / 4 + offset];
      }
    }
    return static_cast<int32_t>(size);
  }

  void Feed(Track &track, bool finishing) {
    if (!track.codec || track.inputEnded) return;
    const size_t audioBlockSize = static_cast<size_t>(1024 * track.channels * 2);
    Buffer input{};
    while ((finishing || (track.video ? !track.pending.empty() : track.pendingBytes >= audioBlockSize)) &&
        Pop(track.inputs, input)) {
      OH_AVCodecBufferAttr attr{};
      if (track.pending.empty()) {
        attr.pts = track.endUs;
        attr.flags = AVCODEC_BUFFER_FLAGS_EOS;
        track.inputEnded = true;
      } else {
        RecordingPacket &packet = track.pending.front();
        attr.pts = packet.timestampUs - track.originUs;
        if (track.video) {
          attr.size = CopyVideo(track, packet, input.value);
          track.packetOffset = packet.data.size();
          track.endUs = attr.pts + 33333;
        } else {
          const size_t alignment = static_cast<size_t>(track.channels) * 2;
          uint8_t *target = OH_AVBuffer_GetAddr(input.value);
          if (!target || audioBlockSize > static_cast<size_t>(OH_AVBuffer_GetCapacity(input.value))) {
            throw std::runtime_error("Invalid encoder audio buffer");
          }
          attr.pts += static_cast<int64_t>(std::llround(
              static_cast<double>(track.packetOffset / alignment) * 1000000 / track.sampleRate));
          attr.size = static_cast<int32_t>(audioBlockSize);
          std::memset(target, 0, audioBlockSize);

          // RTC packets need not contain 1024 samples. Join them and pad only the final AAC block.
          size_t copied = 0;
          while (copied < audioBlockSize && !track.pending.empty()) {
            RecordingPacket &front = track.pending.front();
            const size_t length = std::min(audioBlockSize - copied, front.data.size() - track.packetOffset);
            std::memcpy(target + copied, front.data.data() + track.packetOffset, length);
            copied += length;
            track.packetOffset += length;
            track.pendingBytes -= length;
            if (track.packetOffset == front.data.size()) ReleasePacket(track);
          }
          track.endUs = attr.pts + 1024LL * 1000000 / track.sampleRate;
        }
      }

      Check(OH_AVBuffer_SetBufferAttr(input.value, &attr), "Set encoder input");
      Check(track.video ? OH_VideoEncoder_PushInputBuffer(track.codec, input.index) :
          OH_AudioCodec_PushInputBuffer(track.codec, input.index), "Submit recording frame");
      if (track.video && !track.pending.empty() && track.packetOffset == track.pending.front().data.size()) {
        track.pendingBytes -= track.pending.front().data.size();
        ReleasePacket(track);
      }
      if (track.inputEnded) break;
    }
  }

  void ReleasePacket(Track &track) {
    std::lock_guard<std::mutex> lock(mutex_);
    retainedBytes_ -= track.pending.front().data.size();
    retainedPackets_--;
    track.pending.pop_front();
    track.packetOffset = 0;
  }

  /** Creates container metadata explicitly instead of reusing an encoder's private output format. */
  Format MuxerFormat(Track &track, OH_AVBuffer *config) {
    Format format(track.video ?
        OH_AVFormat_CreateVideoFormat(OH_AVCODEC_MIMETYPE_VIDEO_AVC, track.width, track.height) :
        OH_AVFormat_CreateAudioFormat(OH_AVCODEC_MIMETYPE_AUDIO_AAC, track.sampleRate, track.channels),
        OH_AVFormat_Destroy);
    if (!format) throw std::runtime_error("Cannot create MP4 track format");
    if (!track.video) {
      OH_AVFormat_SetIntValue(format.get(), OH_MD_KEY_PROFILE, AAC_PROFILE_LC);
      OH_AVFormat_SetIntValue(format.get(), OH_MD_KEY_AAC_IS_ADTS, 0);
    }

    Format description(track.video ? OH_VideoEncoder_GetOutputDescription(track.codec) :
        OH_AudioCodec_GetOutputDescription(track.codec), OH_AVFormat_Destroy);
    uint8_t *codecData = nullptr;
    size_t codecSize = 0;
    if (description && OH_AVFormat_GetBuffer(description.get(), OH_MD_KEY_CODEC_CONFIG, &codecData, &codecSize) &&
        codecData && codecSize > 0) {
      OH_AVFormat_SetBuffer(format.get(), OH_MD_KEY_CODEC_CONFIG, codecData, codecSize);
    }
    if (config) {
      OH_AVCodecBufferAttr attr{};
      Check(OH_AVBuffer_GetBufferAttr(config, &attr), "Read codec configuration");
      const uint8_t *address = OH_AVBuffer_GetAddr(config);
      if (!address || attr.offset < 0 || attr.size <= 0 ||
          static_cast<int64_t>(attr.offset) + attr.size > OH_AVBuffer_GetCapacity(config)) {
        throw std::runtime_error("Invalid codec configuration");
      }
      OH_AVFormat_SetBuffer(format.get(), OH_MD_KEY_CODEC_CONFIG,
          const_cast<uint8_t *>(address + attr.offset), attr.size);
    }
    return format;
  }

  void OpenTrackMuxer(Track &track, OH_AVBuffer *config) {
    Format format = MuxerFormat(track, config);
    const std::string path = path_ + (track.video ? ".video.mp4" : ".audio.mp4");
    track.fd = open(path.c_str(), O_CREAT | O_EXCL | O_RDWR, 0600);
    if (track.fd < 0) throw std::runtime_error("Cannot create encoded track");
    track.muxer = OH_AVMuxer_Create(track.fd, AV_OUTPUT_FORMAT_MPEG_4);
    if (!track.muxer) throw std::runtime_error("Cannot create track muxer");
    const std::string operation = track.video ? "Add encoded video track" : "Add encoded audio track";
    Check(OH_AVMuxer_AddTrack(track.muxer, &track.muxerTrack, format.get()), operation.c_str());
    Check(OH_AVMuxer_Start(track.muxer), "Start track muxer");
  }

  void Drain(Track &track) {
    Buffer output{};
    while (Pop(track.outputs, output)) {
      try {
        OH_AVCodecBufferAttr attr{};
        Check(OH_AVBuffer_GetBufferAttr(output.value, &attr), "Read encoder output");
        const bool config = (attr.flags & AVCODEC_BUFFER_FLAGS_CODEC_DATA) != 0;
        if (attr.size > 0) {
          if (!track.muxer) OpenTrackMuxer(track, config ? output.value : nullptr);
          if (!config || (attr.flags & AVCODEC_BUFFER_FLAGS_SYNC_FRAME) != 0) {
            Check(OH_AVMuxer_WriteSampleBuffer(track.muxer, track.muxerTrack, output.value), "Write encoded track");
            track.written++;
          }
        }
        if ((attr.flags & AVCODEC_BUFFER_FLAGS_EOS) != 0) track.outputEnded = true;
      } catch (...) {
        ReleaseOutput(track, output.index);
        throw;
      }
      ReleaseOutput(track, output.index);
    }
  }

  void ReleaseOutput(Track &track, uint32_t index) {
    Check(track.video ? OH_VideoEncoder_FreeOutputBuffer(track.codec, index) :
        OH_AudioCodec_FreeOutputBuffer(track.codec, index), "Release encoded frame");
  }

  void CloseTrack(Track &track, bool validate) {
    // Never hold the callback mutex while stopping or destroying a codec.
    if (track.codec) {
      if (track.started) {
        if (track.video) OH_VideoEncoder_Stop(track.codec);
        else OH_AudioCodec_Stop(track.codec);
      }
      if (track.video) OH_VideoEncoder_Destroy(track.codec);
      else OH_AudioCodec_Destroy(track.codec);
      track.codec = nullptr;
    }
    OH_AVErrCode result = AV_ERR_OK;
    if (track.muxer) {
      result = OH_AVMuxer_Stop(track.muxer);
      OH_AVMuxer_Destroy(track.muxer);
      track.muxer = nullptr;
    }
    if (track.fd >= 0) { close(track.fd); track.fd = -1; }
    if (validate) Check(result, "Finish encoded track");
  }

  void Merge() {
    if (video_.written == 0) throw std::runtime_error("No generated video frames were recorded");
    const int fd = open(path_.c_str(), O_CREAT | O_EXCL | O_RDWR, 0600);
    if (fd < 0) throw std::runtime_error("Cannot create recording");
    OH_AVMuxer *muxer = OH_AVMuxer_Create(fd, AV_OUTPUT_FORMAT_MPEG_4);
    if (!muxer) { close(fd); throw std::runtime_error("Cannot create final muxer"); }

    try {
      TrackReader video, audio;
      const bool hasAudio = audio_.written > 0;
      const int64_t originUs = hasAudio ? std::min(video_.originUs, audio_.originUs) : video_.originUs;
      video.offsetUs = video_.originUs - originUs;
      audio.offsetUs = audio_.originUs - originUs;
      video.Open(path_ + ".video.mp4", muxer, video_.width * video_.height * 3 / 2 + 65536);
      if (hasAudio) audio.Open(path_ + ".audio.mp4", muxer, 65536);
      else audio.ended = true;
      Check(OH_AVMuxer_SetRotation(muxer, video_.rotation), "Set recording rotation");
      Check(OH_AVMuxer_Start(muxer), "Start final muxer");

      while (!video.ended || !audio.ended) {
        TrackReader &next = audio.ended || (!video.ended && video.attr.pts <= audio.attr.pts) ? video : audio;
        Check(OH_AVMuxer_WriteSampleBuffer(muxer, next.outputTrack, next.buffer), "Write final recording");
        next.Read();
      }
      Check(OH_AVMuxer_Stop(muxer), "Finish recording");
    } catch (...) {
      OH_AVMuxer_Destroy(muxer);
      close(fd);
      throw;
    }
    OH_AVMuxer_Destroy(muxer);
    close(fd);
  }

  void Run() {
    bool success = false;
    try {
      while (true) {
        RecordingPacket packet;
        bool available = false, finishing = false;
        {
          std::unique_lock<std::mutex> lock(mutex_);
          changed_.wait_for(lock, std::chrono::milliseconds(5));
          if (cancelled_) break;
          if (!error_.empty()) throw std::runtime_error(error_);
          if (stopping_ && Clock::now() > deadline_) throw std::runtime_error("Recording encoder timed out");
          if (!incoming_.empty()) {
            packet = std::move(incoming_.front());
            incoming_.pop_front();
            available = true;
          }
          finishing = stopping_ && incoming_.empty();
        }

        if (available) Enqueue(std::move(packet));
        Feed(video_, finishing);
        Feed(audio_, finishing);
        Drain(video_);
        Drain(audio_);
        if (finishing && (!video_.codec || video_.outputEnded) && (!audio_.codec || audio_.outputEnded)) {
          CloseTrack(video_, true);
          CloseTrack(audio_, true);
          Merge();
          success = true;
          break;
        }
      }
    } catch (const std::exception &error) {
      {
        std::lock_guard<std::mutex> lock(mutex_);
        if (error_.empty()) error_ = error.what();
      }
      failure_(error.what());
    }

    CloseTrack(video_, false);
    CloseTrack(audio_, false);
    unlink((path_ + ".video.mp4").c_str());
    unlink((path_ + ".audio.mp4").c_str());
    if (!success) unlink(path_.c_str());
  }
};

RealtimeRecorder::RealtimeRecorder(std::string path, std::function<void(std::string)> failure)
    : state_(std::make_unique<State>(std::move(path), std::move(failure))) {}

RealtimeRecorder::~RealtimeRecorder() = default;

void RealtimeRecorder::Append(RecordingPacket packet) {
  state_->Append(std::move(packet));
}

std::string RealtimeRecorder::Finish(bool cancel) {
  return state_->Finish(cancel);
}

} // namespace xlab
