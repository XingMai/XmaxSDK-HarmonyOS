//
//  AudioFrame.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/** RTC 外部音频链路使用的单声道 PCM 音频帧。 */
export class AudioFrame {

  /** PCM 输出规格 */
  static readonly SAMPLE_RATE: number = 48000;
  static readonly CHANNEL_COUNT: number = 1;
  static readonly SAMPLES_PER_FRAME: number = 480;

  /** PCM 数据与播放时间 */
  readonly data: Uint8Array;
  readonly timestampUs: number;

  /**
   * 创建48 kHz 单声道 PCM 音频帧。
   *
   * @param data 当前帧的有效媒体数据。
   * @param timestampUs 媒体帧时间戳，单位微秒。
   * @returns 新建的 AudioFrame 实例。
   */
  constructor(
    data: Uint8Array,
    timestampUs: number
  ) {
    this.data = data;
    this.timestampUs = timestampUs;
  }
}
