#ifndef XMAX_AUDIO_PCM_CONVERTER_H
#define XMAX_AUDIO_PCM_CONVERTER_H

#include <cstddef>
#include <cstdint>
#include <functional>
#include <vector>

namespace xmax {
class AudioPcmConverter {
 public:
  using PacketHandler = std::function<void(
      std::vector<uint8_t>,
      int64_t)>;

  AudioPcmConverter(
      int32_t sourceSampleRate,
      int32_t sourceChannelCount,
      int64_t mediaStartUs,
      int64_t cycleDurationUs);

  bool Append(
      const uint8_t* data,
      size_t length,
      int64_t timestampUs,
      const PacketHandler& handler);

  void Finish(const PacketHandler& handler);

 private:
  void AppendSilence(
      int64_t sampleCount,
      const PacketHandler& handler);

  void AppendSample(
      int16_t sample,
      const PacketHandler& handler);

  int16_t ReadMonoSample(
      const uint8_t* frame) const;

  int32_t sourceSampleRate_ = 0;
  int32_t sourceChannelCount_ = 0;
  int64_t mediaStartUs_ = 0;
  int64_t cycleSampleCount_ = 0;
  int64_t scheduledSampleCount_ = 0;

  bool hasSourceSample_ = false;
  int16_t previousSourceSample_ = 0;
  int64_t sourceSampleIndex_ = 0;
  double nextOutputPosition_ = 0;

  std::vector<int16_t> packetSamples_;
};
}  // namespace xmax

#endif
