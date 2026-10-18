//
//  MediaTimeline.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import systemDateTime from '@ohos.systemDateTime';

const PLAYBACK_START_DELAY_US: number = 100000;
const AUDIO_PACKET_DURATION_US: number = 10000;

/** 音频和视频文件采集共享的单调播放时间轴。 */
export class MediaTimeline {

  /** 媒体时间轴基准 */
  readonly mediaStartUs: number;
  readonly cycleDurationUs: number;

  /** 单调播放锚点与暂停补偿 */
  private readonly playbackAnchorUs: number;
  private accumulatedPauseUs: number = 0;
  private pausedAtUs: number = -1;

  /**
   * 创建媒体播放时间轴。
   *
   * @param mediaStartUs 媒体时间轴的起始时间，单位微秒。
   * @param mediaDurationUs 媒体有效播放时长，单位微秒。
   * @returns 新建的 MediaTimeline 实例。
   */
  constructor(
    mediaStartUs: number,
    mediaDurationUs: number
  ) {
    this.mediaStartUs = mediaStartUs;
    this.cycleDurationUs = Math.ceil(
      mediaDurationUs / AUDIO_PACKET_DURATION_US
    ) * AUDIO_PACKET_DURATION_US;
    this.playbackAnchorUs = MediaTimeline.currentTimestampUs() +
      PLAYBACK_START_DELAY_US;
  }

  /**
   * 读取媒体播放使用的单调时间。
   *
   * @returns 以微秒为单位的当前单调时间。
   */
  static currentTimestampUs(): number {
    const uptimeNs: number = systemDateTime.getUptime(
      systemDateTime.TimeType.ACTIVE,
      true
    );

    return Math.floor(uptimeNs / 1000);
  }

  /**
   * 计算指定循环轮次的播放锚点，计入累计暂停时长。
   *
   * @param loopIndex 从 0 开始的媒体循环轮次。
   * @returns 该轮播放对应的单调时间锚点，单位微秒。
   */
  playbackAnchorForLoop(loopIndex: number): number {
    return this.playbackAnchorUs + this.accumulatedPauseUs +
      loopIndex * this.cycleDurationUs;
  }

  /**
   * 冻结共享媒体时间轴。
   *
   * @returns 无返回值。
   */
  pause(): void {
    if (this.pausedAtUs < 0) {
      this.pausedAtUs = MediaTimeline.currentTimestampUs();
    }
  }

  /**
   * 恢复共享媒体时间轴。
   *
   * @returns 本次暂停持续时间，供已创建的音视频解码器同步平移播放锚点。
   */
  resume(): number {
    if (this.pausedAtUs < 0) {
      return 0;
    }
    const durationUs: number = Math.max(
      MediaTimeline.currentTimestampUs() - this.pausedAtUs,
      0
    );
    this.pausedAtUs = -1;
    this.accumulatedPauseUs += durationUs;
    return durationUs;
  }
}
