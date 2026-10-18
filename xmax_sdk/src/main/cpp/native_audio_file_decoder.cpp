//
//  native_audio_file_decoder.cpp
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

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

#include <unistd.h>

#include "audio_pcm_converter.h"
#include "multimedia/player_framework/native_avbuffer.h"
#include "multimedia/player_framework/native_avcodec_audiocodec.h"
#include "multimedia/player_framework/native_avcodec_base.h"
#include "multimedia/player_framework/native_avdemuxer.h"
#include "multimedia/player_framework/native_avformat.h"
#include "multimedia/player_framework/native_avsource.h"

namespace {
/**
 * 携带 PCM 音频、播放时间戳及结束或错误通知。
 */
struct DecodedAudioPacket {

  /** PCM 数据与播放时间 */
  std::vector<uint8_t> data;
  int64_t timestampUs = 0;

  /** 结束与错误通知 */
  bool endOfStream = false;
  std::string error;
};

/**
 * 连续解码本地音频，转换为 48 kHz 单声道 PCM 并按播放时间轴输出。
 */
class NativeAudioFileDecoder {
 public:
  /**
   * 创建音频文件解码器。
   *
   * @returns 无返回值；完成实例初始化。
   */
  NativeAudioFileDecoder() = default;

  /**
   * 停止媒体输出并释放实例持有的原生资源与缓存。
   *
   * @returns 无返回值。
   */
  ~NativeAudioFileDecoder() {
    Stop();
  }

  /**
   * 创建并配置原生媒体资源，准备按目标规格输出媒体数据。
   *
   * @param env 当前 ArkTS N-API 执行环境。
   * @param listener 用于交付媒体帧、结束或错误通知的 ArkTS 函数。
   * @param sourceFd 由调用方打开的文件描述符；解码器会复制描述符以独立管理生命周期。
   * @param sourceSize 源文件的字节长度。
   * @param playbackAnchorUs 媒体起点对应的单调播放锚点，单位微秒。
   * @param mediaStartUs 源媒体时间轴起点，单位微秒。
   * @param cycleDurationUs 一轮媒体播放时长，单位微秒。
   * @param error 写入失败原因的字符串指针。
   * @returns 初始化成功时返回 true；失败返回 false 并写入错误说明。
   */
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

    int32_t sampleRate = 0;
    int32_t channelCount = 0;
    const char* mime = nullptr;
    if (!OH_AVFormat_GetStringValue(
            trackFormat_, OH_MD_KEY_CODEC_MIME, &mime) ||
        mime == nullptr ||
        !OH_AVFormat_GetIntValue(
            trackFormat_, OH_MD_KEY_AUD_SAMPLE_RATE, &sampleRate) ||
        !OH_AVFormat_GetIntValue(
            trackFormat_, OH_MD_KEY_AUD_CHANNEL_COUNT, &channelCount) ||
        sampleRate <= 0 || channelCount <= 0) {
      *error = "读取音频轨道格式失败";
      return false;
    }
    OH_AVFormat_SetIntValue(
        trackFormat_,
        OH_MD_KEY_AUDIO_SAMPLE_FORMAT,
        SAMPLE_S16LE);

    converter_ = std::make_unique<xmax::AudioPcmConverter>(
        sampleRate,
        channelCount,
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

  /**
   * 暂停连续媒体输出并唤醒节奏等待，使工作线程响应暂停状态。
   *
   * @returns 无返回值。
   */
  void Pause() {
    if (!running_.load()) {
      return;
    }
    paused_.store(true);
    pacingCondition_.notify_all();
  }

  /**
   * 按暂停时长平移播放锚点，恢复连续媒体输出。
   *
   * @param pausedDurationUs 本次暂停持续时间，单位微秒。
   * @returns 无返回值。
   */
  void Resume(int64_t pausedDurationUs) {
    if (!running_.load()) {
      return;
    }
    if (pausedDurationUs > 0) {
      playbackAnchorUs_.fetch_add(pausedDurationUs);
    }
    paused_.store(false);
    pacingCondition_.notify_all();
  }

  /**
   * 停止媒体输出与相关线程，并释放文件、系统媒体资源和回调引用。
   *
   * @returns 无返回值。
   */
  void Stop() {
    const bool wasRunning = running_.exchange(false);
    paused_.store(false);
    pacingCondition_.notify_all();

    {
      std::lock_guard<std::mutex> lock(demuxerMutex_);
    }

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
  /**
   * 查找并选择有效音频轨道，保存其格式和轨道索引。
   *
   * @param error 写入失败原因的字符串指针。
   * @returns 找到有效音轨时返回 true，否则返回 false 并写入错误。
   */
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

  /**
   * 创建用于向 ArkTS 线程交付媒体结果的线程安全回调。
   *
   * @param env 当前 ArkTS N-API 执行环境。
   * @param listener 用于交付媒体帧、结束或错误通知的 ArkTS 函数。
   * @param error 写入失败原因的字符串指针。
   * @returns 回调创建成功时返回 true，失败时返回 false 并写入错误。
   */
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

  /**
   * 接收系统解码错误，将错误码转换为媒体失败通知。
   *
   * @param errorCode 系统解码器返回的错误码。
   * @param userData 注册系统回调时绑定的原生解码器实例。
   * @returns 无返回值。
   */
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

  /**
   * 同步系统解码器报告的输出格式，供后续帧读取和转换使用。
   *
   * @param format 系统解码器报告的媒体格式。
   * @param userData 注册系统回调时绑定的原生解码器实例。
   * @returns 无返回值。
   */
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

  /**
   * 从选中媒体轨道读取压缩数据，填入解码器请求的输入缓冲区。
   *
   * @param codec 请求或交付缓冲区的系统解码器。
   * @param index 需要提交或归还的系统缓冲区索引。
   * @param buffer 系统解码器提供的媒体缓冲区。
   * @param userData 注册系统回调时绑定的原生解码器实例。
   * @returns 无返回值。
   */
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
    if (!decoder->WaitUntilPlaying()) {
      return;
    }

    OH_AVErrCode readResult = AV_ERR_OK;
    OH_AVErrCode pushResult = AV_ERR_OK;
    {
      std::lock_guard<std::mutex> lock(decoder->demuxerMutex_);
      if (!decoder->running_.load() || decoder->inputEnded_) {
        return;
      }
      readResult = OH_AVDemuxer_ReadSampleBuffer(
          decoder->demuxer_,
          decoder->trackIndex_,
          buffer);
      if (readResult == AV_ERR_OK) {
        OH_AVCodecBufferAttr attr{};
        const bool endOfStream =
            OH_AVBuffer_GetBufferAttr(buffer, &attr) == AV_ERR_OK &&
            (attr.flags & AVCODEC_BUFFER_FLAGS_EOS) != 0;
        pushResult = OH_AudioCodec_PushInputBuffer(codec, index);
        if (pushResult == AV_ERR_OK) {
          decoder->inputEnded_ = endOfStream;
        }
      }
    }
    if (readResult != AV_ERR_OK) {
      decoder->ReportError(
          "读取音频压缩帧失败：" + std::to_string(readResult));
      return;
    }
    if (pushResult != AV_ERR_OK) {
      decoder->ReportError(
          "提交音频压缩帧失败：" + std::to_string(pushResult));
    }
  }

  /**
   * 处理系统解码器输出的媒体缓冲区，并在完成后归还缓冲区索引。
   *
   * @param codec 请求或交付缓冲区的系统解码器。
   * @param index 需要提交或归还的系统缓冲区索引。
   * @param buffer 系统解码器提供的媒体缓冲区。
   * @param userData 注册系统回调时绑定的原生解码器实例。
   * @returns 无返回值。
   */
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

  /**
   * 读取解码缓冲数据及时间戳，转换并按播放时间轴交付媒体帧。
   *
   * @param buffer 系统解码器提供的媒体缓冲区。
   * @returns 无返回值。
   */
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

  /**
   * 将 PCM 数据与对应播放时间封装为音频包并交付到 ArkTS。
   *
   * @param data 需要转移所有权的 PCM 数据。
   * @param timestampUs 媒体输出时间戳，单位微秒。
   * @returns 无返回值。
   */
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

  /**
   * 按目标播放时间等待，同时响应暂停和停止请求，避免解码输出快于播放进度。
   *
   * @param timestampUs 媒体输出时间戳，单位微秒。
   * @returns 无返回值。
   */
  void Pace(int64_t timestampUs) {
    std::unique_lock<std::mutex> lock(pacingMutex_);
    while (running_.load()) {
      pacingCondition_.wait(lock, [this] {
        return !running_.load() || !paused_.load();
      });
      if (!running_.load()) {
        return;
      }
      const auto deadline = std::chrono::steady_clock::time_point(
          std::chrono::microseconds(PlaybackTimestampUs(timestampUs)));
      if (!pacingCondition_.wait_until(lock, deadline, [this] {
            return !running_.load() || paused_.load();
          })) {
        return;
      }
    }
  }

  /**
   * 等待媒体恢复播放或停止，供解码回调遵守暂停状态。
   *
   * @returns 仍在运行且允许播放时返回 true，已经停止时返回 false。
   */
  bool WaitUntilPlaying() {
    std::unique_lock<std::mutex> lock(pacingMutex_);
    pacingCondition_.wait(lock, [this] {
      return !running_.load() || !paused_.load();
    });
    return running_.load();
  }

  /**
   * 将媒体时间戳映射为包含暂停补偿的单调播放时间。
   *
   * @param mediaTimestampUs 源媒体时间戳，单位微秒。
   * @returns 以微秒为单位的播放时间戳。
   */
  int64_t PlaybackTimestampUs(int64_t mediaTimestampUs) const {
    return playbackAnchorUs_.load() + std::max<int64_t>(
        mediaTimestampUs - mediaStartUs_,
        0);
  }

  /**
   * 仅通知一次媒体处理错误，避免重复错误回调。
   *
   * @param message 需要交付或记录的错误原因。
   * @returns 无返回值。
   */
  void ReportError(const std::string& message) {
    if (reportedError_.exchange(true)) {
      return;
    }

    auto* packet = new DecodedAudioPacket();
    packet->error = message;
    Dispatch(packet);
  }

  /**
   * 将媒体数据包提交到 ArkTS 线程安全回调队列；提交失败时释放数据包。
   *
   * @param packet 需要消费、交付或释放的媒体数据包。
   * @returns 无返回值。
   */
  void Dispatch(DecodedAudioPacket* packet) {
    if (listener_ == nullptr ||
        napi_call_threadsafe_function(
            listener_, packet, napi_tsfn_nonblocking) != napi_ok) {
      delete packet;
    }
  }

  /**
   * 在 ArkTS 线程交付媒体数据或状态通知，并按交付结果转移或释放数据包。
   *
   * @param env 当前 ArkTS N-API 执行环境。
   * @param callback 需要在 ArkTS 线程调用的函数。
   * @param data 关联的原生数据包或异步任务上下文。
   * @returns 无返回值。
   */
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

  /** 文件、解封装与音频解码资源 */
  int32_t fd_ = -1;
  OH_AVSource* source_ = nullptr;
  OH_AVDemuxer* demuxer_ = nullptr;
  OH_AVCodec* decoder_ = nullptr;
  OH_AVFormat* trackFormat_ = nullptr;
  uint32_t trackIndex_ = 0;

  /** ArkTS 结果通知 */
  napi_threadsafe_function listener_ = nullptr;

  /** 运行、暂停与错误去重状态 */
  std::atomic<bool> running_{false};
  std::atomic<bool> paused_{false};
  std::atomic<bool> reportedError_{false};

  /** 解封装并发访问与输入结束状态 */
  std::mutex demuxerMutex_;
  bool inputEnded_ = false;

  /** 播放节奏等待与单调时间轴 */
  std::mutex pacingMutex_;
  std::condition_variable pacingCondition_;

  std::atomic<int64_t> playbackAnchorUs_{0};
  int64_t mediaStartUs_ = 0;

  /** PCM 重采样与组包 */
  std::unique_ptr<xmax::AudioPcmConverter> converter_;
};

/**
 * 从 ArkTS 对象中读取其绑定的原生文件解码器。
 *
 * @param env 当前 ArkTS N-API 执行环境。
 * @param info 当前 ArkTS 方法调用的参数与接收对象。
 * @returns 有效解码器指针；调用无效时返回空指针并抛出异常。
 */
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

/**
 * 将 ArkTS 暂停请求转交给原生文件解码器。
 *
 * @param env 当前 ArkTS N-API 执行环境。
 * @param info 当前 ArkTS 方法调用的参数与接收对象。
 * @returns ArkTS undefined。
 */
napi_value PauseDecoder(
    napi_env env,
    napi_callback_info info) {
  NativeAudioFileDecoder* decoder = UnwrapDecoder(env, info);
  if (decoder == nullptr) {
    napi_throw_error(env, nullptr, "Audio decoder is unavailable");
    return nullptr;
  }
  decoder->Pause();
  napi_value result = nullptr;
  napi_get_undefined(env, &result);
  return result;
}

/**
 * 读取暂停时长并恢复原生文件解码输出。
 *
 * @param env 当前 ArkTS N-API 执行环境。
 * @param info 当前 ArkTS 方法调用的参数与接收对象。
 * @returns ArkTS undefined；参数无效时抛出异常。
 */
napi_value ResumeDecoder(
    napi_env env,
    napi_callback_info info) {
  size_t argumentCount = 1;
  napi_value argument = nullptr;
  napi_value receiver = nullptr;
  if (napi_get_cb_info(
          env, info, &argumentCount, &argument, &receiver, nullptr) != napi_ok ||
      argumentCount != 1) {
    napi_throw_type_error(env, nullptr, "Expected paused duration");
    return nullptr;
  }
  NativeAudioFileDecoder* decoder = nullptr;
  double pausedDurationUs = 0;
  if (napi_unwrap(
          env, receiver, reinterpret_cast<void**>(&decoder)) != napi_ok ||
      decoder == nullptr ||
      napi_get_value_double(env, argument, &pausedDurationUs) != napi_ok ||
      pausedDurationUs < 0) {
    napi_throw_type_error(env, nullptr, "Audio decoder resume arguments are invalid");
    return nullptr;
  }
  decoder->Resume(static_cast<int64_t>(pausedDurationUs));
  napi_value result = nullptr;
  napi_get_undefined(env, &result);
  return result;
}

/**
 * 在 ArkTS 解码器对象回收时删除原生实例并释放媒体资源。
 *
 * @param data 关联的原生数据包或异步任务上下文。
 * @returns 无返回值。
 */
void FinalizeDecoder(napi_env, void* data, void*) {
  delete static_cast<NativeAudioFileDecoder*>(data);
}

/**
 * 释放 ArkTS 对象绑定的原生文件解码器。
 *
 * @param env 当前 ArkTS N-API 执行环境。
 * @param info 当前 ArkTS 方法调用的参数与接收对象。
 * @returns ArkTS undefined。
 */
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

/**
 * 解析文件与播放参数，创建并启动原生 PCM 音频解码器。
 *
 * @param env 当前 ArkTS N-API 执行环境。
 * @param info 当前 ArkTS 方法调用的参数与接收对象。
 * @returns 包装原生音频解码器的 ArkTS 对象；失败时抛出异常。
 */
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
  napi_property_descriptor descriptors[] = {
      {
          "pause", nullptr, PauseDecoder, nullptr, nullptr, nullptr,
          napi_default, nullptr
      },
      {
          "resume", nullptr, ResumeDecoder, nullptr, nullptr, nullptr,
          napi_default, nullptr
      },
      {
          "release", nullptr, ReleaseDecoder, nullptr, nullptr, nullptr,
          napi_default, nullptr
      }
  };
  napi_define_properties(
      env,
      result,
      sizeof(descriptors) / sizeof(descriptors[0]),
      descriptors);
  napi_wrap(
      env,
      result,
      decoder,
      FinalizeDecoder,
      nullptr,
      nullptr);
  return result;
}
}  /** namespace */

namespace xmax {
/**
 * 向原生模块导出音频文件解码器的创建入口。
 *
 * @param env 当前 ArkTS N-API 执行环境。
 * @param exports 需要挂载 SDK 原生入口的模块导出对象。
 * @returns 无返回值。
 */
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
}  /** namespace xmax */
