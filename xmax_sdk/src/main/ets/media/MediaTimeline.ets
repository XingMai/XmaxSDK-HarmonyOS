import systemDateTime from '@ohos.systemDateTime';

const PLAYBACK_START_DELAY_US: number = 100000;
const AUDIO_PACKET_DURATION_US: number = 10000;

/** 音频和视频文件采集共享的单调播放时间轴。 */
export class MediaTimeline {
  readonly mediaStartUs: number;
  readonly cycleDurationUs: number;

  private readonly playbackAnchorUs: number;
  private accumulatedPauseUs: number = 0;
  private pausedAtUs: number = -1;

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

  static currentTimestampUs(): number {
    const uptimeNs: number = systemDateTime.getUptime(
      systemDateTime.TimeType.ACTIVE,
      true
    );

    return Math.floor(uptimeNs / 1000);
  }

  playbackAnchorForLoop(loopIndex: number): number {
    return this.playbackAnchorUs + this.accumulatedPauseUs +
      loopIndex * this.cycleDurationUs;
  }

  /** 冻结共享媒体时间轴。 */
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
