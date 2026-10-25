//
//  MediaTimeline.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import systemDateTime from '@ohos.systemDateTime';

const PLAYBACK_START_DELAY_US: number = 100000;
const AUDIO_PACKET_DURATION_US: number = 10000;

/** A monotonic playback timeline shared by file audio and video. */
export class MediaTimeline {

  /** The source media timeline origin, in microseconds. */
  readonly mediaStartUs: number;

  /** The duration of one playback cycle, in microseconds. */
  readonly cycleDurationUs: number;

  /** The monotonic playback anchor, in microseconds. */
  private readonly playbackAnchorUs: number;

  /** The accumulated pause duration, in microseconds. */
  private accumulatedPauseUs: number = 0;

  /** The monotonic pause start time, in microseconds. */
  private pausedAtUs: number = -1;

  /**
   * Creates a media playback timeline.
   *
   * @param mediaStartUs The media timeline origin, in microseconds.
   * @param mediaDurationUs The effective playback duration, in microseconds.
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
   * Returns monotonic playback time.
   *
   * @returns The current monotonic time, in microseconds.
   */
  static currentTimestampUs(): number {
    const uptimeNs: number = systemDateTime.getUptime(
      systemDateTime.TimeType.ACTIVE,
      true
    );

    return Math.floor(uptimeNs / 1000);
  }

  /**
   * Resolves a playback cycle anchor including accumulated pauses.
   *
   * @param loopIndex The zero-based playback cycle index.
   *
   * @returns The cycle's monotonic playback anchor, in microseconds.
   */
  playbackAnchorForLoop(
    loopIndex: number
  ): number {
    return this.playbackAnchorUs + this.accumulatedPauseUs +
      loopIndex * this.cycleDurationUs;
  }

  /** Freezes the shared media timeline. */
  pause(): void {
    if (this.pausedAtUs < 0) {
      this.pausedAtUs = MediaTimeline.currentTimestampUs();
    }
  }

  /**
   * Resumes the shared media timeline.
   *
   * @returns The pause duration used to shift existing audio/video decoder anchors.
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
