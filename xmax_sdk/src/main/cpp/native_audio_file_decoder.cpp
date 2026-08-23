#include "native_audio_file_decoder.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

#include <sys/stat.h>
#include <unistd.h>

#include "audio_pcm_converter.h"
#include "multimedia/player_framework/native_avbuffer.h"
#include "multimedia/player_framework/native_avcodec_audiocodec.h"
#include "multimedia/player_framework/native_avcodec_base.h"
#include "multimedia/player_framework/native_avdemuxer.h"
#include "multimedia/player_framework/native_avformat.h"
#include "multimedia/player_framework/native_avsource.h"

namespace {
struct DecodedAudioPacket {
  std::vector<uint8_t> data;
  int64_t timestampUs = 0;
  bool endOfStream = false;
  std::string error;
};

class NativeAudioFileDecoder {
 public:
  NativeAudioFileDecoder() = default;

  ~NativeAudioFileDecoder() {
    Stop();
  }

  bool Initialize(
      napi_env env,
      napi_value listener,
      int32_t sourceFd,
      int64_t sourceSize,
      int64_t playbackAnchorUs,
      int64_t mediaStartUs,
      int64_t cycleDurationUs,
      std::string* error) {
    playbackAnchorUs_ = playbackAnchorUs;
    mediaStartUs_ = mediaStartUs;

    fd_ = dup(sourceFd);
    if (fd_ < 0) {
      *error = "复制音频文件描述符失败";
      return false;
    }

    source_ = OH_AVSource_CreateWithFD(fd_, 0, sourceSize);
    if (source_ == nullptr) {
      *error = "创建音频数据源失败";
      return false;
    }
    if (!SelectAudioTrack(error)) {
      return false;
    }

    const char* mime = nullptr;
    if (!OH_AVFormat_GetStringValue(
            trackFormat_, OH_MD_KEY_CODEC_MIME, &mime) ||
        mime == nullptr ||
        !OH_AVFormat_GetIntValue(
            trackFormat_, OH_MD_KEY_AUD_SAMPLE_RATE, &sampleRate_) ||
        !OH_AVFormat_GetIntValue(
            trackFormat_, OH_MD_KEY_AUD_CHANNEL_COUNT, &channelCount_) ||
        sampleRate_ <= 0 || channelCount_ <= 0) {
      *error = "读取音频轨道格式失败";
      return false;
    }
    OH_AVFormat_SetIntValue(
        trackFormat_,
        OH_MD_KEY_AUDIO_SAMPLE_FORMAT,
        SAMPLE_S16LE);

    converter_ = std::make_unique<xmax::AudioPcmConverter>(
        sampleRate_,
        channelCount_,
        mediaStartUs_,
        cycleDurationUs);
    demuxer_ = OH_AVDemuxer_CreateWithSource(source_);
    if (demuxer_ == nullptr ||
        OH_AVDemuxer_SelectTrackByID(
            demuxer_, trackIndex_) != AV_ERR_OK) {
      *error = "创建音频解封装器失败";
      return false;
    }

    decoder_ = OH_AudioCodec_CreateByMime(mime, false);
    if (decoder_ == nullptr) {
      *error = "当前设备不支持所选音频编码";
      return false;
    }
    if (!CreateListener(env, listener, error)) {
      return false;
    }

    const OH_AVCodecCallback callbacks{
        OnError,
        OnStreamChanged,
        OnNeedInputBuffer,
        OnNewOutputBuffer
    };
    if (OH_AudioCodec_RegisterCallback(
            decoder_, callbacks, this) != AV_ERR_OK ||
        OH_AudioCodec_Configure(decoder_, trackFormat_) != AV_ERR_OK ||
        OH_AudioCodec_Prepare(decoder_) != AV_ERR_OK) {
      *error = "配置 PCM 音频连续解码失败";
      return false;
    }

    running_.store(true);
    if (OH_AudioCodec_Start(decoder_) != AV_ERR_OK) {
      running_.store(false);
      *error = "启动音频连续解码失败";
      return false;
    }

    return true;
  }

  void Stop() {
    const bool wasRunning = running_.exchange(false);
    pacingCondition_.notify_all();

    if (decoder_ != nullptr) {
      if (wasRunning) {
        OH_AudioCodec_Stop(decoder_);
      }
      OH_AudioCodec_Destroy(decoder_);
      decoder_ = nullptr;
    }
    if (listener_ != nullptr) {
      napi_release_threadsafe_function(
          listener_,
          napi_tsfn_abort);
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

    converter_.reset();
  }

 private:
  bool SelectAudioTrack(std::string* error) {
    OH_AVFormat* sourceFormat = OH_AVSource_GetSourceFormat(source_);
    int32_t trackCount = 0;
    if (sourceFormat == nullptr ||
        !OH_AVFormat_GetIntValue(
            sourceFormat, OH_MD_KEY_TRACK_COUNT, &trackCount) ||
        trackCount <= 0) {
      if (sourceFormat != nullptr) {
        OH_AVFormat_Destroy(sourceFormat);
      }
      *error = "读取音频轨道数量失败";
      return false;
    }
    OH_AVFormat_Destroy(sourceFormat);

    for (int32_t index = 0; index < trackCount; ++index) {
      OH_AVFormat* candidate = OH_AVSource_GetTrackFormat(
          source_,
          index);
      int32_t trackType = -1;
      if (candidate != nullptr &&
          OH_AVFormat_GetIntValue(
              candidate, OH_MD_KEY_TRACK_TYPE, &trackType) &&
          trackType == MEDIA_TYPE_AUD) {
        trackIndex_ = static_cast<uint32_t>(index);
        trackFormat_ = candidate;
        return true;
      }

      if (candidate != nullptr) {
        OH_AVFormat_Destroy(candidate);
      }
    }

    *error = "视频文件中没有可解码的音频轨道";
    return false;
  }

  bool CreateListener(
      napi_env env,
      napi_value listener,
      std::string* error) {
    napi_value resourceName = nullptr;
    if (napi_create_string_utf8(
            env,
            "XmaxNativeAudioFileDecoder",
            NAPI_AUTO_LENGTH,
            &resourceName) != napi_ok ||
        napi_create_threadsafe_function(
            env,
            listener,
            nullptr,
            resourceName,
            16,
            1,
            nullptr,
            nullptr,
            nullptr,
            CallListener,
            &listener_) != napi_ok) {
      *error = "创建音频解码回调失败";
      return false;
    }

    return true;
  }

  static void OnError(
      OH_AVCodec*,
      int32_t errorCode,
      void* userData) {
    auto* decoder = static_cast<NativeAudioFileDecoder*>(userData);
    if (decoder != nullptr) {
      decoder->ReportError(
          "音频解码器错误：" + std::to_string(errorCode));
    }
  }

  static void OnStreamChanged(
      OH_AVCodec*,
      OH_AVFormat* format,
      void* userData) {
    auto* decoder = static_cast<NativeAudioFileDecoder*>(userData);
    if (decoder == nullptr || format == nullptr) {
      return;
    }

    int32_t sampleFormat = SAMPLE_S16LE;
    if (OH_AVFormat_GetIntValue(
            format,
            OH_MD_KEY_AUDIO_SAMPLE_FORMAT,
            &sampleFormat) &&
        sampleFormat != SAMPLE_S16LE) {
      decoder->ReportError(
          "音频解码器未输出 16-bit PCM 数据");
    }
  }

  static void OnNeedInputBuffer(
      OH_AVCodec* codec,
      uint32_t index,
      OH_AVBuffer* buffer,
      void* userData) {
    auto* decoder = static_cast<NativeAudioFileDecoder*>(userData);
    if (decoder == nullptr || !decoder->running_.load() ||
        buffer == nullptr) {
      return;
    }

    OH_AVErrCode readResult;
    {
      std::lock_guard<std::mutex> lock(decoder->demuxerMutex_);
      readResult = OH_AVDemuxer_ReadSampleBuffer(
          decoder->demuxer_,
          decoder->trackIndex_,
          buffer);
    }
    if (readResult != AV_ERR_OK) {
      decoder->ReportError(
          "读取音频压缩帧失败：" + std::to_string(readResult));
      return;
    }

    const OH_AVErrCode pushResult = OH_AudioCodec_PushInputBuffer(
        codec,
        index);
    if (pushResult != AV_ERR_OK) {
      decoder->ReportError(
          "提交音频压缩帧失败：" + std::to_string(pushResult));
    }
  }

  static void OnNewOutputBuffer(
      OH_AVCodec* codec,
      uint32_t index,
      OH_AVBuffer* buffer,
      void* userData) {
    auto* decoder = static_cast<NativeAudioFileDecoder*>(userData);
    if (decoder == nullptr || buffer == nullptr) {
      if (codec != nullptr) {
        OH_AudioCodec_FreeOutputBuffer(codec, index);
      }
      return;
    }

    decoder->HandleOutputBuffer(buffer);
    OH_AudioCodec_FreeOutputBuffer(codec, index);
  }

  void HandleOutputBuffer(OH_AVBuffer* buffer) {
    if (!running_.load() || converter_ == nullptr) {
      return;
    }

    OH_AVCodecBufferAttr attr{};
    if (OH_AVBuffer_GetBufferAttr(buffer, &attr) != AV_ERR_OK) {
      ReportError("读取解码音频帧属性失败");
      return;
    }

    const xmax::AudioPcmConverter::PacketHandler handler =
        [this](std::vector<uint8_t> data, int64_t timestampUs) {
          DispatchAudioPacket(
              std::move(data),
              timestampUs);
        };
    if ((attr.flags & AVCODEC_BUFFER_FLAGS_EOS) != 0) {
      converter_->Finish(handler);
      if (running_.load()) {
        auto* packet = new DecodedAudioPacket();
        packet->endOfStream = true;
        Dispatch(packet);
      }
      return;
    }
    if (attr.size <= 0 || attr.offset < 0) {
      return;
    }

    uint8_t* address = OH_AVBuffer_GetAddr(buffer);
    const int32_t capacity = OH_AVBuffer_GetCapacity(buffer);
    if (address == nullptr || capacity < 0 ||
        static_cast<int64_t>(attr.offset) +
            static_cast<int64_t>(attr.size) > capacity) {
      ReportError("访问 PCM 音频解码帧失败");
      return;
    }

    if (!converter_->Append(
            address + attr.offset,
            static_cast<size_t>(attr.size),
            attr.pts,
            handler)) {
      ReportError("转换 PCM 音频解码帧失败");
    }
  }

  void DispatchAudioPacket(
      std::vector<uint8_t> data,
      int64_t timestampUs) {
    Pace(timestampUs);
    if (!running_.load()) {
      return;
    }

    const int64_t playbackTimestampUs = PlaybackTimestampUs(
        timestampUs);
    const int64_t currentTimestampUs = std::chrono::duration_cast<
        std::chrono::microseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count();
    if (currentTimestampUs - playbackTimestampUs > 30000) {
      return;
    }

    auto* packet = new DecodedAudioPacket();
    packet->data = std::move(data);
    packet->timestampUs = playbackTimestampUs;
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

    auto* packet = new DecodedAudioPacket();
    packet->error = message;
    Dispatch(packet);
  }

  void Dispatch(DecodedAudioPacket* packet) {
    if (listener_ == nullptr ||
        napi_call_threadsafe_function(
            listener_, packet, napi_tsfn_nonblocking) != napi_ok) {
      delete packet;
    }
  }

  static void CallListener(
      napi_env env,
      napi_value callback,
      void*,
      void* data) {
    auto* packet = static_cast<DecodedAudioPacket*>(data);
    if (packet == nullptr) {
      return;
    }
    if (env == nullptr || callback == nullptr) {
      delete packet;
      return;
    }

    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    napi_value arguments[4] = {
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
    napi_create_double(
        env,
        static_cast<double>(packet->timestampUs),
        &arguments[1]);
    napi_get_boolean(
        env,
        packet->endOfStream,
        &arguments[2]);
    if (!packet->error.empty()) {
      napi_create_string_utf8(
          env,
          packet->error.c_str(),
          NAPI_AUTO_LENGTH,
          &arguments[3]);
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
  std::mutex pacingMutex_;
  std::condition_variable pacingCondition_;

  int32_t sampleRate_ = 0;
  int32_t channelCount_ = 0;
  int64_t playbackAnchorUs_ = 0;
  int64_t mediaStartUs_ = 0;
  std::unique_ptr<xmax::AudioPcmConverter> converter_;
};

NativeAudioFileDecoder* UnwrapDecoder(
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

  NativeAudioFileDecoder* decoder = nullptr;
  if (napi_unwrap(
          env,
          thisValue,
          reinterpret_cast<void**>(&decoder)) != napi_ok) {
    return nullptr;
  }

  return decoder;
}

void FinalizeDecoder(napi_env, void* data, void*) {
  delete static_cast<NativeAudioFileDecoder*>(data);
}

napi_value ReleaseDecoder(
    napi_env env,
    napi_callback_info info) {
  NativeAudioFileDecoder* decoder = UnwrapDecoder(env, info);
  if (decoder != nullptr) {
    decoder->Stop();
  }

  napi_value result = nullptr;
  napi_get_undefined(env, &result);
  return result;
}

napi_value CreateAudioFileDecoder(
    napi_env env,
    napi_callback_info info) {
  size_t argumentCount = 6;
  napi_value arguments[6] = {
      nullptr,
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
      argumentCount != 6) {
    napi_throw_type_error(
        env,
        nullptr,
        "Expected fd, size, playback timing and frame listener");
    return nullptr;
  }

  int32_t fd = -1;
  double sourceSize = 0;
  double playbackAnchorUs = 0;
  double mediaStartUs = 0;
  double cycleDurationUs = 0;
  napi_valuetype listenerType = napi_undefined;
  if (napi_get_value_int32(env, arguments[0], &fd) != napi_ok ||
      napi_get_value_double(env, arguments[1], &sourceSize) != napi_ok ||
      napi_get_value_double(env, arguments[2], &playbackAnchorUs) != napi_ok ||
      napi_get_value_double(env, arguments[3], &mediaStartUs) != napi_ok ||
      napi_get_value_double(env, arguments[4], &cycleDurationUs) != napi_ok ||
      fd < 0 || sourceSize <= 0 || playbackAnchorUs <= 0 ||
      cycleDurationUs <= 0 ||
      napi_typeof(env, arguments[5], &listenerType) != napi_ok ||
      listenerType != napi_function) {
    napi_throw_type_error(
        env,
        nullptr,
        "Audio file decoder arguments are invalid");
    return nullptr;
  }

  auto* decoder = new NativeAudioFileDecoder();
  std::string error;
  if (!decoder->Initialize(
          env,
          arguments[5],
          fd,
          static_cast<int64_t>(sourceSize),
          static_cast<int64_t>(playbackAnchorUs),
          static_cast<int64_t>(mediaStartUs),
          static_cast<int64_t>(cycleDurationUs),
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
void DefineNativeAudioFileDecoder(
    napi_env env,
    napi_value exports) {
  napi_property_descriptor descriptor = {
      "createAudioFileDecoder",
      nullptr,
      CreateAudioFileDecoder,
      nullptr,
      nullptr,
      nullptr,
      napi_default,
      nullptr
  };
  napi_define_properties(env, exports, 1, &descriptor);
}
}  // namespace xmax
