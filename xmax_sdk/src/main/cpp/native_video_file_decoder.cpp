#include "native_video_file_decoder.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#include <sys/stat.h>
#include <unistd.h>

#include "multimedia/player_framework/native_avbuffer.h"
#include "multimedia/player_framework/native_avcodec_base.h"
#include "multimedia/player_framework/native_avcodec_videodecoder.h"
#include "multimedia/player_framework/native_avdemuxer.h"
#include "multimedia/player_framework/native_avformat.h"
#include "multimedia/player_framework/native_avsource.h"

namespace {
struct DecodedFramePacket {
  std::vector<uint8_t> data;
  int32_t width = 0;
  int32_t height = 0;
  int32_t stride = 0;
  int64_t timestampUs = 0;
  bool endOfStream = false;
  std::string error;
};

class NativeVideoFileDecoder {
 public:
  NativeVideoFileDecoder() = default;

  ~NativeVideoFileDecoder() {
    Stop();
  }

  bool Initialize(
      napi_env env,
      napi_value listener,
      int32_t sourceFd,
      int64_t sourceSize,
      int64_t playbackAnchorUs,
      int64_t mediaStartUs,
      std::string* error) {
    playbackAnchorUs_ = playbackAnchorUs;
    mediaStartUs_ = mediaStartUs;

    fd_ = dup(sourceFd);
    if (fd_ < 0) {
      *error = "复制视频文件描述符失败";
      return false;
    }

    source_ = OH_AVSource_CreateWithFD(fd_, 0, sourceSize);
    if (source_ == nullptr) {
      *error = "创建视频数据源失败";
      return false;
    }

    OH_AVFormat* sourceFormat = OH_AVSource_GetSourceFormat(source_);
    int32_t trackCount = 0;
    if (sourceFormat == nullptr ||
        !OH_AVFormat_GetIntValue(
            sourceFormat, OH_MD_KEY_TRACK_COUNT, &trackCount) ||
        trackCount <= 0) {
      if (sourceFormat != nullptr) {
        OH_AVFormat_Destroy(sourceFormat);
      }
      *error = "读取视频轨道数量失败";
      return false;
    }
    OH_AVFormat_Destroy(sourceFormat);

    for (int32_t index = 0; index < trackCount; ++index) {
      OH_AVFormat* candidate = OH_AVSource_GetTrackFormat(source_, index);
      int32_t trackType = -1;
      if (candidate != nullptr &&
          OH_AVFormat_GetIntValue(
              candidate, OH_MD_KEY_TRACK_TYPE, &trackType) &&
          trackType == MEDIA_TYPE_VID) {
        trackIndex_ = static_cast<uint32_t>(index);
        trackFormat_ = candidate;
        break;
      }
      if (candidate != nullptr) {
        OH_AVFormat_Destroy(candidate);
      }
    }
    if (trackFormat_ == nullptr) {
      *error = "视频文件中没有可解码的视频轨道";
      return false;
    }

    const char* mime = nullptr;
    if (!OH_AVFormat_GetStringValue(
            trackFormat_, OH_MD_KEY_CODEC_MIME, &mime) ||
        mime == nullptr ||
        !OH_AVFormat_GetIntValue(
            trackFormat_, OH_MD_KEY_WIDTH, &width_) ||
        !OH_AVFormat_GetIntValue(
            trackFormat_, OH_MD_KEY_HEIGHT, &height_) ||
        width_ <= 0 || height_ <= 0) {
      *error = "读取视频轨道格式失败";
      return false;
    }
    stride_ = width_;
    sliceHeight_ = height_;
    pixelFormat_ = AV_PIXEL_FORMAT_NV12;
    OH_AVFormat_SetIntValue(
        trackFormat_, OH_MD_KEY_PIXEL_FORMAT, AV_PIXEL_FORMAT_NV12);

    demuxer_ = OH_AVDemuxer_CreateWithSource(source_);
    if (demuxer_ == nullptr ||
        OH_AVDemuxer_SelectTrackByID(
            demuxer_, trackIndex_) != AV_ERR_OK) {
      *error = "创建视频解封装器失败";
      return false;
    }

    decoder_ = OH_VideoDecoder_CreateByMime(mime);
    if (decoder_ == nullptr) {
      *error = "当前设备不支持所选视频编码";
      return false;
    }

    napi_value resourceName = nullptr;
    if (napi_create_string_utf8(
            env,
            "XmaxNativeVideoFileDecoder",
            NAPI_AUTO_LENGTH,
            &resourceName) != napi_ok ||
        napi_create_threadsafe_function(
            env,
            listener,
            nullptr,
            resourceName,
            4,
            1,
            nullptr,
            nullptr,
            nullptr,
            CallListener,
            &listener_) != napi_ok) {
      *error = "创建视频解码回调失败";
      return false;
    }

    const OH_AVCodecCallback callbacks{
        OnError,
        OnStreamChanged,
        OnNeedInputBuffer,
        OnNewOutputBuffer
    };
    if (OH_VideoDecoder_RegisterCallback(
            decoder_, callbacks, this) != AV_ERR_OK ||
        OH_VideoDecoder_Configure(decoder_, trackFormat_) != AV_ERR_OK ||
        OH_VideoDecoder_Prepare(decoder_) != AV_ERR_OK) {
      *error = "配置 NV12 视频连续解码失败";
      return false;
    }

    running_.store(true);
    if (OH_VideoDecoder_Start(decoder_) != AV_ERR_OK) {
      running_.store(false);
      *error = "启动视频连续解码失败";
      return false;
    }
    return true;
  }

  void Stop() {
    const bool wasRunning = running_.exchange(false);
    pacingCondition_.notify_all();
    if (decoder_ != nullptr) {
      if (wasRunning) {
        OH_VideoDecoder_Stop(decoder_);
      }
      OH_VideoDecoder_Destroy(decoder_);
      decoder_ = nullptr;
    }
    if (listener_ != nullptr) {
      napi_release_threadsafe_function(listener_, napi_tsfn_abort);
      listener_ = nullptr;
    }
    if (demuxer_ != nullptr) {
      OH_AVDemuxer_Destroy(demuxer_);
      demuxer_ = nullptr;
    }
    if (trackFormat_ != nullptr) {
      OH_AVFormat_Destroy(trackFormat_);
      trackFormat_ = nullptr;
    }
    if (source_ != nullptr) {
      OH_AVSource_Destroy(source_);
      source_ = nullptr;
    }
    if (fd_ >= 0) {
      close(fd_);
      fd_ = -1;
    }
  }

 private:
  static void OnError(
      OH_AVCodec*,
      int32_t errorCode,
      void* userData) {
    auto* decoder = static_cast<NativeVideoFileDecoder*>(userData);
    if (decoder != nullptr) {
      decoder->ReportError(
          "视频解码器错误：" + std::to_string(errorCode));
    }
  }

  static void OnStreamChanged(
      OH_AVCodec*,
      OH_AVFormat* format,
      void* userData) {
    auto* decoder = static_cast<NativeVideoFileDecoder*>(userData);
    if (decoder == nullptr || format == nullptr) {
      return;
    }
    std::lock_guard<std::mutex> lock(decoder->formatMutex_);
    int32_t value = 0;
    if (OH_AVFormat_GetIntValue(
            format, OH_MD_KEY_VIDEO_PIC_WIDTH, &value) ||
        OH_AVFormat_GetIntValue(format, OH_MD_KEY_WIDTH, &value)) {
      decoder->width_ = value;
    }
    if (OH_AVFormat_GetIntValue(
            format, OH_MD_KEY_VIDEO_PIC_HEIGHT, &value) ||
        OH_AVFormat_GetIntValue(format, OH_MD_KEY_HEIGHT, &value)) {
      decoder->height_ = value;
    }
    if (OH_AVFormat_GetIntValue(
            format, OH_MD_KEY_VIDEO_STRIDE, &value)) {
      decoder->stride_ = value;
    }
    if (OH_AVFormat_GetIntValue(
            format, OH_MD_KEY_VIDEO_SLICE_HEIGHT, &value)) {
      decoder->sliceHeight_ = value;
    }
    if (OH_AVFormat_GetIntValue(
            format, OH_MD_KEY_PIXEL_FORMAT, &value)) {
      decoder->pixelFormat_ = value;
    }
  }

  static void OnNeedInputBuffer(
      OH_AVCodec* codec,
      uint32_t index,
      OH_AVBuffer* buffer,
      void* userData) {
    auto* decoder = static_cast<NativeVideoFileDecoder*>(userData);
    if (decoder == nullptr || !decoder->running_.load() ||
        buffer == nullptr) {
      return;
    }

    OH_AVErrCode readResult;
    {
      std::lock_guard<std::mutex> lock(decoder->demuxerMutex_);
      readResult = OH_AVDemuxer_ReadSampleBuffer(
          decoder->demuxer_, decoder->trackIndex_, buffer);
    }
    if (readResult != AV_ERR_OK) {
      decoder->ReportError(
          "读取视频压缩帧失败：" + std::to_string(readResult));
      return;
    }
    const OH_AVErrCode pushResult =
        OH_VideoDecoder_PushInputBuffer(codec, index);
    if (pushResult != AV_ERR_OK) {
      decoder->ReportError(
          "提交视频压缩帧失败：" + std::to_string(pushResult));
    }
  }

  static void OnNewOutputBuffer(
      OH_AVCodec* codec,
      uint32_t index,
      OH_AVBuffer* buffer,
      void* userData) {
    auto* decoder = static_cast<NativeVideoFileDecoder*>(userData);
    if (decoder == nullptr || buffer == nullptr) {
      if (codec != nullptr) {
        OH_VideoDecoder_FreeOutputBuffer(codec, index);
      }
      return;
    }
    decoder->HandleOutputBuffer(buffer);
    OH_VideoDecoder_FreeOutputBuffer(codec, index);
  }

  void HandleOutputBuffer(OH_AVBuffer* buffer) {
    if (!running_.load()) {
      return;
    }
    OH_AVCodecBufferAttr attr{};
    if (OH_AVBuffer_GetBufferAttr(buffer, &attr) != AV_ERR_OK) {
      ReportError("读取解码视频帧属性失败");
      return;
    }
    if ((attr.flags & AVCODEC_BUFFER_FLAGS_EOS) != 0) {
      auto* packet = new DecodedFramePacket();
      packet->endOfStream = true;
      Dispatch(packet);
      return;
    }
    if (attr.size <= 0 || attr.offset < 0) {
      return;
    }

    int32_t width = 0;
    int32_t height = 0;
    int32_t stride = 0;
    int32_t sliceHeight = 0;
    int32_t pixelFormat = 0;
    {
      std::lock_guard<std::mutex> lock(formatMutex_);
      width = width_;
      height = height_;
      stride = stride_;
      sliceHeight = sliceHeight_;
      pixelFormat = pixelFormat_;
    }
    if (pixelFormat != AV_PIXEL_FORMAT_NV12 ||
        width <= 0 || height <= 0) {
      ReportError("视频解码器未输出 NV12 帧");
      return;
    }
    const int32_t minimumStride = width;
    if (stride < minimumStride) {
      ReportError("NV12 视频解码帧宽跨距无效");
      return;
    }
    if (sliceHeight < height) {
      sliceHeight = height;
    }
    const size_t sourceLength = static_cast<size_t>(stride) *
        static_cast<size_t>(sliceHeight + height / 2);
    if (sourceLength > static_cast<size_t>(attr.size)) {
      ReportError("NV12 视频解码帧布局无效");
      return;
    }

    uint8_t* address = OH_AVBuffer_GetAddr(buffer);
    const int32_t capacity = OH_AVBuffer_GetCapacity(buffer);
    if (address == nullptr || capacity < 0 ||
        static_cast<int64_t>(attr.offset) +
            static_cast<int64_t>(sourceLength) > capacity) {
      ReportError("访问 NV12 视频解码帧失败");
      return;
    }

    Pace(attr.pts);
    if (!running_.load()) {
      return;
    }
    auto* packet = new DecodedFramePacket();
    packet->width = width;
    packet->height = height;
    packet->stride = minimumStride;
    packet->timestampUs = PlaybackTimestampUs(attr.pts);
    const size_t targetLumaLength =
        static_cast<size_t>(minimumStride) * static_cast<size_t>(height);
    packet->data.resize(targetLumaLength + targetLumaLength / 2);
    const uint8_t* sourceRow = address + attr.offset;
    uint8_t* targetRow = packet->data.data();
    for (int32_t row = 0; row < height; ++row) {
      std::memcpy(targetRow, sourceRow, minimumStride);
      sourceRow += stride;
      targetRow += minimumStride;
    }
    sourceRow = address + attr.offset +
        static_cast<size_t>(stride) * static_cast<size_t>(sliceHeight);
    targetRow = packet->data.data() + targetLumaLength;
    for (int32_t row = 0; row < height / 2; ++row) {
      std::memcpy(targetRow, sourceRow, minimumStride);
      sourceRow += stride;
      targetRow += minimumStride;
    }
    Dispatch(packet);
  }

  void Pace(int64_t timestampUs) {
    const auto deadline = std::chrono::steady_clock::time_point(
        std::chrono::microseconds(
            PlaybackTimestampUs(timestampUs)));

    std::unique_lock<std::mutex> lock(pacingMutex_);
    pacingCondition_.wait_until(lock, deadline, [this] {
      return !running_.load();
    });
  }

  int64_t PlaybackTimestampUs(int64_t mediaTimestampUs) const {
    return playbackAnchorUs_ + std::max<int64_t>(
        mediaTimestampUs - mediaStartUs_,
        0);
  }

  void ReportError(const std::string& message) {
    if (reportedError_.exchange(true)) {
      return;
    }
    auto* packet = new DecodedFramePacket();
    packet->error = message;
    Dispatch(packet);
  }

  void Dispatch(DecodedFramePacket* packet) {
    if (listener_ == nullptr ||
        napi_call_threadsafe_function(
            listener_, packet, napi_tsfn_blocking) != napi_ok) {
      delete packet;
    }
  }

  static void CallListener(
      napi_env env,
      napi_value callback,
      void*,
      void* data) {
    auto* packet = static_cast<DecodedFramePacket*>(data);
    if (packet == nullptr) {
      return;
    }
    if (env == nullptr || callback == nullptr) {
      delete packet;
      return;
    }

    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    napi_value arguments[7] = {
        undefined,
        undefined,
        undefined,
        undefined,
        undefined,
        undefined,
        undefined
    };
    if (!packet->data.empty()) {
      void* outputAddress = nullptr;
      if (napi_create_arraybuffer(
              env,
              packet->data.size(),
              &outputAddress,
              &arguments[0]) != napi_ok ||
          outputAddress == nullptr) {
        delete packet;
        return;
      }
      std::memcpy(
          outputAddress,
          packet->data.data(),
          packet->data.size());
    }
    napi_create_int32(env, packet->width, &arguments[1]);
    napi_create_int32(env, packet->height, &arguments[2]);
    napi_create_int32(env, packet->stride, &arguments[3]);
    napi_create_double(
        env,
        static_cast<double>(packet->timestampUs),
        &arguments[4]);
    napi_get_boolean(env, packet->endOfStream, &arguments[5]);
    if (!packet->error.empty()) {
      napi_create_string_utf8(
          env,
          packet->error.c_str(),
          NAPI_AUTO_LENGTH,
          &arguments[6]);
    }

    napi_value result = nullptr;
    napi_call_function(
        env,
        undefined,
        callback,
        sizeof(arguments) / sizeof(arguments[0]),
        arguments,
        &result);
    delete packet;
  }

  int32_t fd_ = -1;
  OH_AVSource* source_ = nullptr;
  OH_AVDemuxer* demuxer_ = nullptr;
  OH_AVCodec* decoder_ = nullptr;
  OH_AVFormat* trackFormat_ = nullptr;
  uint32_t trackIndex_ = 0;
  napi_threadsafe_function listener_ = nullptr;

  std::atomic<bool> running_{false};
  std::atomic<bool> reportedError_{false};
  std::mutex demuxerMutex_;
  std::mutex formatMutex_;
  int32_t width_ = 0;
  int32_t height_ = 0;
  int32_t stride_ = 0;
  int32_t sliceHeight_ = 0;
  int32_t pixelFormat_ = 0;

  std::mutex pacingMutex_;
  std::condition_variable pacingCondition_;
  int64_t playbackAnchorUs_ = 0;
  int64_t mediaStartUs_ = 0;
};

NativeVideoFileDecoder* UnwrapDecoder(
    napi_env env,
    napi_callback_info info) {
  size_t argumentCount = 0;
  napi_value thisValue = nullptr;
  if (napi_get_cb_info(
          env,
          info,
          &argumentCount,
          nullptr,
          &thisValue,
          nullptr) != napi_ok) {
    return nullptr;
  }
  NativeVideoFileDecoder* decoder = nullptr;
  if (napi_unwrap(
          env,
          thisValue,
          reinterpret_cast<void**>(&decoder)) != napi_ok) {
    return nullptr;
  }
  return decoder;
}

void FinalizeDecoder(napi_env, void* data, void*) {
  delete static_cast<NativeVideoFileDecoder*>(data);
}

napi_value ReleaseDecoder(
    napi_env env,
    napi_callback_info info) {
  NativeVideoFileDecoder* decoder = UnwrapDecoder(env, info);
  if (decoder != nullptr) {
    decoder->Stop();
  }
  napi_value result = nullptr;
  napi_get_undefined(env, &result);
  return result;
}

napi_value CreateVideoFileDecoder(
    napi_env env,
    napi_callback_info info) {
  size_t argumentCount = 5;
  napi_value arguments[5] = {
      nullptr,
      nullptr,
      nullptr,
      nullptr,
      nullptr
  };
  if (napi_get_cb_info(
          env,
          info,
          &argumentCount,
          arguments,
          nullptr,
          nullptr) != napi_ok ||
      argumentCount != 5) {
    napi_throw_type_error(
        env,
        nullptr,
        "Expected fd, size, playback timing and frame listener");
    return nullptr;
  }

  int32_t fd = -1;
  double sizeValue = 0;
  double playbackAnchorUs = 0;
  double mediaStartUs = 0;
  napi_valuetype listenerType = napi_undefined;
  if (napi_get_value_int32(env, arguments[0], &fd) != napi_ok ||
      napi_get_value_double(env, arguments[1], &sizeValue) != napi_ok ||
      napi_get_value_double(
          env, arguments[2], &playbackAnchorUs) != napi_ok ||
      napi_get_value_double(
          env, arguments[3], &mediaStartUs) != napi_ok ||
      fd < 0 || sizeValue <= 0 ||
      playbackAnchorUs <= 0 ||
      napi_typeof(env, arguments[4], &listenerType) != napi_ok ||
      listenerType != napi_function) {
    napi_throw_type_error(env, nullptr, "Video file decoder arguments are invalid");
    return nullptr;
  }

  auto* decoder = new NativeVideoFileDecoder();
  std::string error;
  if (!decoder->Initialize(
          env,
          arguments[4],
          fd,
          static_cast<int64_t>(sizeValue),
          static_cast<int64_t>(playbackAnchorUs),
          static_cast<int64_t>(mediaStartUs),
          &error)) {
    delete decoder;
    napi_throw_error(env, nullptr, error.c_str());
    return nullptr;
  }

  napi_value result = nullptr;
  napi_create_object(env, &result);
  napi_property_descriptor descriptor = {
      "release",
      nullptr,
      ReleaseDecoder,
      nullptr,
      nullptr,
      nullptr,
      napi_default,
      nullptr
  };
  napi_define_properties(env, result, 1, &descriptor);
  napi_wrap(
      env,
      result,
      decoder,
      FinalizeDecoder,
      nullptr,
      nullptr);
  return result;
}
}  // namespace

namespace xmax {
void DefineNativeVideoFileDecoder(
    napi_env env,
    napi_value exports) {
  napi_property_descriptor descriptor = {
      "createVideoFileDecoder",
      nullptr,
      CreateVideoFileDecoder,
      nullptr,
      nullptr,
      nullptr,
      napi_default,
      nullptr
  };
  napi_define_properties(env, exports, 1, &descriptor);
}
}  // namespace xmax
