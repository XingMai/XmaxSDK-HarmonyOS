//
//  audio_pcm_converter.cpp
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
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
} // namespace

namespace xmax {

/**
 * Creates a PCM converter.
 *
 * @param sourceSampleRate The source PCM sample rate, in Hz.
 * @param sourceChannelCount The source PCM channel count.
 * @param mediaStartUs The source media timeline origin, in microseconds.
 * @param cycleDurationUs The duration of one playback cycle, in microseconds.
 */
AudioPcmConverter::AudioPcmConverter(int32_t sourceSampleRate,
    int32_t sourceChannelCount,
    int64_t mediaStartUs,
    int64_t cycleDurationUs)
    : sourceSampleRate_(sourceSampleRate), sourceChannelCount_(sourceChannelCount),
      mediaStartUs_(mediaStartUs) {
  const int64_t packetCount =
      std::max<int64_t>(1, (cycleDurationUs + kPacketDurationUs - 1) / kPacketDurationUs);
  cycleSampleCount_ = packetCount * kSamplesPerPacket;
  packetSamples_.reserve(kSamplesPerPacket);
}

/**
 * Appends source PCM and delivers complete audio packets. Partial source sample frames are invalid.
 *
 * @param data The read-only source PCM, valid for the duration of the call.
 * @param length The input byte count, containing complete source sample frames.
 * @param timestampUs The output media timestamp, in microseconds.
 * @param handler The receiver for complete PCM packets and their microsecond timestamps.
 * @return True if the input is valid and accepted; false for invalid length or channel layout.
 */
bool AudioPcmConverter::Append(const uint8_t *data,
    size_t length,
    int64_t timestampUs,
    const PacketHandler &handler) {
  if (data == nullptr || sourceSampleRate_ <= 0 || sourceChannelCount_ <= 0) {
    return false;
  }

  const size_t frameSize = static_cast<size_t>(sourceChannelCount_) * kBytesPerSample;
  if (frameSize == 0 || length % frameSize != 0) {
    return false;
  }

  if (!hasSourceSample_) {
    const int64_t initialSilenceSamples =
        std::max<int64_t>(0, (timestampUs - mediaStartUs_) * kTargetSampleRate / 1000000);
    AppendSilence(initialSilenceSamples, handler);
  }

  const size_t frameCount = length / frameSize;
  const double sourceStep =
      static_cast<double>(sourceSampleRate_) / static_cast<double>(kTargetSampleRate);
  for (size_t index = 0; index < frameCount; ++index) {
    const int16_t currentSample = ReadMonoSample(data + index * frameSize);

    if (!hasSourceSample_) {
      hasSourceSample_ = true;
      previousSourceSample_ = currentSample;
      sourceSampleIndex_ = 0;
      nextOutputPosition_ = 0;
    }

    const double currentPosition = static_cast<double>(sourceSampleIndex_);
    const double previousPosition = std::max(0.0, currentPosition - 1.0);
    while (nextOutputPosition_ <= currentPosition) {
      const double fraction =
          currentPosition == previousPosition ? 0.0 : nextOutputPosition_ - previousPosition;
      const double interpolated = static_cast<double>(previousSourceSample_) +
          (static_cast<double>(currentSample) - static_cast<double>(previousSourceSample_)) *
              fraction;
      const double clamped = std::clamp(interpolated,
          static_cast<double>(std::numeric_limits<int16_t>::min()),
          static_cast<double>(std::numeric_limits<int16_t>::max()));
      AppendSample(static_cast<int16_t>(std::lround(clamped)), handler);
      nextOutputPosition_ += sourceStep;
    }

    previousSourceSample_ = currentSample;
    sourceSampleIndex_++;
  }

  return true;
}

/**
 * Pads the final audio packet and delivers remaining PCM at end of file.
 *
 * @param handler The receiver for complete PCM packets and their microsecond timestamps.
 */
void AudioPcmConverter::Finish(const PacketHandler &handler) {
  if (packetSamples_.empty()) {
    return;
  }
  AppendSilence(static_cast<int64_t>(kSamplesPerPacket - packetSamples_.size()), handler);
}

/**
 * Appends output-rate silence to compensate for audio-track start or end gaps.
 *
 * @param sampleCount The number of output samples to append.
 * @param handler The receiver for complete PCM packets and their microsecond timestamps.
 */
void AudioPcmConverter::AppendSilence(int64_t sampleCount, const PacketHandler &handler) {
  for (int64_t index = 0; index < sampleCount; ++index) {
    AppendSample(0, handler);
  }
}

/**
 * Appends one output sample and delivers complete packets with timestamps.
 *
 * @param sample The mono signed 16-bit PCM sample to append.
 * @param handler The receiver for complete PCM packets and their microsecond timestamps.
 */
void AudioPcmConverter::AppendSample(int16_t sample, const PacketHandler &handler) {
  if (scheduledSampleCount_ >= cycleSampleCount_) {
    return;
  }

  packetSamples_.push_back(sample);
  scheduledSampleCount_++;
  if (packetSamples_.size() < kSamplesPerPacket) {
    return;
  }

  std::vector<uint8_t> packet(kSamplesPerPacket * kBytesPerSample);
  std::memcpy(packet.data(), packetSamples_.data(), packet.size());
  packetSamples_.clear();

  const int64_t packetStartSample = scheduledSampleCount_ - kSamplesPerPacket;
  const int64_t timestampUs = mediaStartUs_ + packetStartSample * 1000000 / kTargetSampleRate;
  handler(std::move(packet), timestampUs);
}

/**
 * Mixes one source sample frame into a mono signed 16-bit sample.
 *
 * @param frame One PCM sample frame containing all source channels.
 * @return The average of the source channels.
 */
int16_t AudioPcmConverter::ReadMonoSample(const uint8_t *frame) const {
  int64_t sampleSum = 0;
  for (int32_t channel = 0; channel < sourceChannelCount_; ++channel) {
    int16_t sample = 0;
    std::memcpy(&sample, frame + channel * kBytesPerSample, sizeof(sample));
    sampleSum += sample;
  }

  return static_cast<int16_t>(sampleSum / sourceChannelCount_);
}
} // namespace xmax
