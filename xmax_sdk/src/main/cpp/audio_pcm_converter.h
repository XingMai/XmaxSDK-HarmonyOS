//
//  audio_pcm_converter.h
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
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
/**
 * 将源 PCM 重采样为 48 kHz 单声道 10 毫秒音频包，维护连续播放时间戳。
 */
class AudioPcmConverter {
 public:
  /**
   * 接收转换后的 PCM 音频包和微秒时间戳；数据所有权随参数转移给回调。
   */
  using PacketHandler = std::function<void(
      std::vector<uint8_t>,
      int64_t)>;

  /**
   * 创建 PCM 转换器。
   *
   * @param sourceSampleRate 源 PCM 采样率，单位 Hz。
   * @param sourceChannelCount 源 PCM 声道数。
   * @param mediaStartUs 源媒体时间轴起点，单位微秒。
   * @param cycleDurationUs 一轮媒体播放时长，单位微秒。
   * @returns 无返回值；完成实例初始化。
   */
  AudioPcmConverter(
      int32_t sourceSampleRate,
      int32_t sourceChannelCount,
      int64_t mediaStartUs,
      int64_t cycleDurationUs);

  /**
   * 追加源 PCM 数据，通过回调输出完整音频包；不完整的源采样帧视为无效输入。
   *
   * @param data 只读源 PCM 数据，缓冲区应在调用期间有效。
   * @param length 输入 PCM 数据的字节数，必须包含完整源采样帧。
   * @param timestampUs 媒体输出时间戳，单位微秒。
   * @param handler 接收完整 PCM 包及其微秒时间戳的回调。
   * @returns 数据格式有效且已接收时返回 true，输入长度或声道布局无效时返回 false。
   */
  bool Append(
      const uint8_t* data,
      size_t length,
      int64_t timestampUs,
      const PacketHandler& handler);

  /**
   * 在文件结束时补齐当前音频包，并输出剩余 PCM 数据。
   *
   * @param handler 接收完整 PCM 包及其微秒时间戳的回调。
   * @returns 无返回值。
   */
  void Finish(const PacketHandler& handler);

 private:
  /**
   * 按输出采样率追加指定数量的静音样本，补偿音轨起点或尾部。
   *
   * @param sampleCount 需要追加的输出样本数。
   * @param handler 接收完整 PCM 包及其微秒时间戳的回调。
   * @returns 无返回值。
   */
  void AppendSilence(
      int64_t sampleCount,
      const PacketHandler& handler);

  /**
   * 追加单个输出样本，达到一包长度后交付 PCM 数据和时间戳。
   *
   * @param sample 待追加的单声道 16 位 PCM 样本。
   * @param handler 接收完整 PCM 包及其微秒时间戳的回调。
   * @returns 无返回值。
   */
  void AppendSample(
      int16_t sample,
      const PacketHandler& handler);

  /**
   * 将一个源采样帧的各声道混合为单声道有符号 16 位样本。
   *
   * @param frame 包含所有源声道的单个 PCM 采样帧。
   * @returns 声道平均后的单声道样本。
   */
  int16_t ReadMonoSample(
      const uint8_t* frame) const;

  /** 源 PCM 格式与播放基准 */
  int32_t sourceSampleRate_ = 0;
  int32_t sourceChannelCount_ = 0;
  int64_t mediaStartUs_ = 0;
  int64_t cycleSampleCount_ = 0;
  int64_t scheduledSampleCount_ = 0;

  /** 重采样位置与前一源样本 */
  bool hasSourceSample_ = false;
  int16_t previousSourceSample_ = 0;
  int64_t sourceSampleIndex_ = 0;
  double nextOutputPosition_ = 0;

  /** 待交付的单声道音频包 */
  std::vector<int16_t> packetSamples_;
};
}  /** namespace xmax */

#endif
