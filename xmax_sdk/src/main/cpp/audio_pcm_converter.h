//
//  audio_pcm_converter.h
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

#ifndef XMAX_AUDIO_PCM_CONVERTER_H
#define XMAX_AUDIO_PCM_CONVERTER_H

#include <cstddef>
#include <cstdint>
#include <functional>
#include <vector>

namespace xmax {

/** Resamples PCM into 48 kHz mono 10 ms packets with continuous playback timestamps. */
class AudioPcmConverter {
public:
  /** Receives converted PCM packets and microsecond timestamps, taking ownership of the data. */
  using PacketHandler = std::function<void(std::vector<uint8_t>, int64_t)>;

  /**
   * Creates a PCM converter.
   *
   * @param sourceSampleRate The source PCM sample rate, in Hz.
   * @param sourceChannelCount The source PCM channel count.
   * @param mediaStartUs The source media timeline origin, in microseconds.
   * @param cycleDurationUs The duration of one playback cycle, in microseconds.
   */
  AudioPcmConverter(int32_t sourceSampleRate,
      int32_t sourceChannelCount,
      int64_t mediaStartUs,
      int64_t cycleDurationUs);

  /**
   * Appends source PCM and delivers complete audio packets. Partial source sample frames are invalid.
   *
   * @param data The read-only source PCM, valid for the duration of the call.
   * @param length The input byte count, containing complete source sample frames.
   * @param timestampUs The output media timestamp, in microseconds.
   * @param handler The receiver for complete PCM packets and their microsecond timestamps.
   * @return True if the input is valid and accepted; false for invalid length or channel layout.
   */
  bool Append(const uint8_t *data,
      size_t length,
      int64_t timestampUs,
      const PacketHandler &handler);

  /**
   * Pads the final audio packet and delivers remaining PCM at end of file.
   *
   * @param handler The receiver for complete PCM packets and their microsecond timestamps.
   */
  void Finish(const PacketHandler &handler);

private:
  /**
   * Appends output-rate silence to compensate for audio-track start or end gaps.
   *
   * @param sampleCount The number of output samples to append.
   * @param handler The receiver for complete PCM packets and their microsecond timestamps.
   */
  void AppendSilence(int64_t sampleCount, const PacketHandler &handler);

  /**
   * Appends one output sample and delivers complete packets with timestamps.
   *
   * @param sample The mono signed 16-bit PCM sample to append.
   * @param handler The receiver for complete PCM packets and their microsecond timestamps.
   */
  void AppendSample(int16_t sample, const PacketHandler &handler);

  /**
   * Mixes one source sample frame into a mono signed 16-bit sample.
   *
   * @param frame One PCM sample frame containing all source channels.
   * @return The average of the source channels.
   */
  int16_t ReadMonoSample(const uint8_t *frame) const;

  // Source PCM format and playback origin

  /** The source PCM sample rate, in Hz. */
  int32_t sourceSampleRate_ = 0;

  /** The channel count in source PCM. */
  int32_t sourceChannelCount_ = 0;

  /** The source media timeline origin, in microseconds. */
  int64_t mediaStartUs_ = 0;

  /** The output sample count spanning one playback cycle. */
  int64_t cycleSampleCount_ = 0;

  /** The output samples already scheduled for this cycle. */
  int64_t scheduledSampleCount_ = 0;

  // Resampling position and previous source sample

  /** Whether a previous sample is available for interpolation. */
  bool hasSourceSample_ = false;

  /** The previous source sample retained for resampling. */
  int16_t previousSourceSample_ = 0;

  /** The current source sample position. */
  int64_t sourceSampleIndex_ = 0;

  /** The source position of the next resampled output sample. */
  double nextOutputPosition_ = 0;

  // Pending mono audio packet

  /** The mono output samples waiting for a complete audio packet. */
  std::vector<int16_t> packetSamples_;
};
} // namespace xmax

#endif
