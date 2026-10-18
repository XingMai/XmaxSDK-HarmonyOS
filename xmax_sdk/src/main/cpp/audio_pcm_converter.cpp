//
//  audio_pcm_converter.cpp
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

#include "audio_pcm_converter.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <limits>
#include <utility>

namespace {
constexpr int32_t kTargetSampleRate = 48000;
constexpr int32_t kSamplesPerPacket = 480;
constexpr int32_t kBytesPerSample = 2;
constexpr int64_t kPacketDurationUs = 10000;
}  /** namespace */

namespace xmax {
/**
 * 创建 PCM 转换器。
 *
 * @param sourceSampleRate 源 PCM 采样率，单位 Hz。
 * @param sourceChannelCount 源 PCM 声道数。
 * @param mediaStartUs 源媒体时间轴起点，单位微秒。
 * @param cycleDurationUs 一轮媒体播放时长，单位微秒。
 * @returns 无返回值；完成实例初始化。
 */
AudioPcmConverter::AudioPcmConverter(
    int32_t sourceSampleRate,
    int32_t sourceChannelCount,
    int64_t mediaStartUs,
    int64_t cycleDurationUs)
    : sourceSampleRate_(sourceSampleRate),
      sourceChannelCount_(sourceChannelCount),
      mediaStartUs_(mediaStartUs) {
  const int64_t packetCount = std::max<int64_t>(
      1,
      (cycleDurationUs + kPacketDurationUs - 1) /
          kPacketDurationUs);
  cycleSampleCount_ = packetCount * kSamplesPerPacket;
  packetSamples_.reserve(kSamplesPerPacket);
}

/**
 * 追加源 PCM 数据，通过回调输出完整音频包；不完整的源采样帧视为无效输入。
 *
 * @param data 只读源 PCM 数据，缓冲区应在调用期间有效。
 * @param length 输入 PCM 数据的字节数，必须包含完整源采样帧。
 * @param timestampUs 媒体输出时间戳，单位微秒。
 * @param handler 接收完整 PCM 包及其微秒时间戳的回调。
 * @returns 数据格式有效且已接收时返回 true，输入长度或声道布局无效时返回 false。
 */
bool AudioPcmConverter::Append(
    const uint8_t* data,
    size_t length,
    int64_t timestampUs,
    const PacketHandler& handler) {
  if (data == nullptr || sourceSampleRate_ <= 0 ||
      sourceChannelCount_ <= 0) {
    return false;
  }

  const size_t frameSize = static_cast<size_t>(sourceChannelCount_) *
      kBytesPerSample;
  if (frameSize == 0 || length % frameSize != 0) {
    return false;
  }

  if (!hasSourceSample_) {
    const int64_t initialSilenceSamples = std::max<int64_t>(
        0,
        (timestampUs - mediaStartUs_) * kTargetSampleRate /
            1000000);
    AppendSilence(initialSilenceSamples, handler);
  }

  const size_t frameCount = length / frameSize;
  const double sourceStep = static_cast<double>(sourceSampleRate_) /
      static_cast<double>(kTargetSampleRate);
  for (size_t index = 0; index < frameCount; ++index) {
    const int16_t currentSample = ReadMonoSample(
        data + index * frameSize);

    if (!hasSourceSample_) {
      hasSourceSample_ = true;
      previousSourceSample_ = currentSample;
      sourceSampleIndex_ = 0;
      nextOutputPosition_ = 0;
    }

    const double currentPosition = static_cast<double>(
        sourceSampleIndex_);
    const double previousPosition = std::max(
        0.0,
        currentPosition - 1.0);
    while (nextOutputPosition_ <= currentPosition) {
      const double fraction = currentPosition == previousPosition ?
          0.0 :
          nextOutputPosition_ - previousPosition;
      const double interpolated = static_cast<double>(
          previousSourceSample_) +
          (static_cast<double>(currentSample) -
              static_cast<double>(previousSourceSample_)) * fraction;
      const double clamped = std::clamp(
          interpolated,
          static_cast<double>(std::numeric_limits<int16_t>::min()),
          static_cast<double>(std::numeric_limits<int16_t>::max()));
      AppendSample(
          static_cast<int16_t>(std::lround(clamped)),
          handler);
      nextOutputPosition_ += sourceStep;
    }

    previousSourceSample_ = currentSample;
    sourceSampleIndex_++;
  }

  return true;
}

/**
 * 在文件结束时补齐当前音频包，并输出剩余 PCM 数据。
 *
 * @param handler 接收完整 PCM 包及其微秒时间戳的回调。
 * @returns 无返回值。
 */
void AudioPcmConverter::Finish(
    const PacketHandler& handler) {
  if (packetSamples_.empty()) {
    return;
  }
  AppendSilence(
      static_cast<int64_t>(kSamplesPerPacket - packetSamples_.size()),
      handler);
}

/**
 * 按输出采样率追加指定数量的静音样本，补偿音轨起点或尾部。
 *
 * @param sampleCount 需要追加的输出样本数。
 * @param handler 接收完整 PCM 包及其微秒时间戳的回调。
 * @returns 无返回值。
 */
void AudioPcmConverter::AppendSilence(
    int64_t sampleCount,
    const PacketHandler& handler) {
  for (int64_t index = 0; index < sampleCount; ++index) {
    AppendSample(0, handler);
  }
}

/**
 * 追加单个输出样本，达到一包长度后交付 PCM 数据和时间戳。
 *
 * @param sample 待追加的单声道 16 位 PCM 样本。
 * @param handler 接收完整 PCM 包及其微秒时间戳的回调。
 * @returns 无返回值。
 */
void AudioPcmConverter::AppendSample(
    int16_t sample,
    const PacketHandler& handler) {
  if (scheduledSampleCount_ >= cycleSampleCount_) {
    return;
  }

  packetSamples_.push_back(sample);
  scheduledSampleCount_++;
  if (packetSamples_.size() < kSamplesPerPacket) {
    return;
  }

  std::vector<uint8_t> packet(
      kSamplesPerPacket * kBytesPerSample);
  std::memcpy(
      packet.data(),
      packetSamples_.data(),
      packet.size());
  packetSamples_.clear();

  const int64_t packetStartSample =
      scheduledSampleCount_ - kSamplesPerPacket;
  const int64_t timestampUs = mediaStartUs_ +
      packetStartSample * 1000000 / kTargetSampleRate;
  handler(std::move(packet), timestampUs);
}

/**
 * 将一个源采样帧的各声道混合为单声道有符号 16 位样本。
 *
 * @param frame 包含所有源声道的单个 PCM 采样帧。
 * @returns 声道平均后的单声道样本。
 */
int16_t AudioPcmConverter::ReadMonoSample(
    const uint8_t* frame) const {
  int64_t sampleSum = 0;
  for (int32_t channel = 0;
      channel < sourceChannelCount_;
      ++channel) {
    int16_t sample = 0;
    std::memcpy(
        &sample,
        frame + channel * kBytesPerSample,
        sizeof(sample));
    sampleSum += sample;
  }

  return static_cast<int16_t>(
      sampleSum / sourceChannelCount_);
}
}  /** namespace xmax */
