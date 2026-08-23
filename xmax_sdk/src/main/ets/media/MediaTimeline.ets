import systemDateTime from '@ohos.systemDateTime';

const PLAYBACK_START_DELAY_US: number = 100000;
const AUDIO_PACKET_DURATION_US: number = 10000;

/** 音频和视频文件采集共享的单调播放时间轴。 */
export class MediaTimeline {
  readonly mediaStartUs: number;
  readonly cycleDurationUs: number;

  private readonly playbackAnchorUs: number;

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
    return this.playbackAnchorUs + loopIndex * this.cycleDurationUs;
  }
}
