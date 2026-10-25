//
//  RemoteAudioTimeline.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { RtcRemoteAudioFrame } from '../../foundation/rtc/RtcRemoteAudioFrame';
import { RealtimeAudioFrame } from '../../service/realtime/RealtimeMediaFrame';

/** A normalized PCM packet and its track-continuity flag. */
export class ResolvedRemoteAudioFrame {

  /** The packet timed by exact sample count from its native anchor. */
  readonly frame: RealtimeAudioFrame;

  /** Whether the native clock or PCM format started a new continuous run. */
  readonly isDiscontinuous: boolean;

  /** Creates a normalized audio result. */
  constructor(
    frame: RealtimeAudioFrame,
    isDiscontinuous: boolean
  ) {
    this.frame = frame;
    this.isDiscontinuous = isDiscontinuous;
  }
}

/** Advances PCM by sample count without independently zeroing the native audio origin. */
export class RemoteAudioTimeline {

  /** The native clock anchor for the current continuous run, in microseconds. */
  private anchorUs: number | undefined;

  /** The samples per channel already timed from the current anchor. */
  private samples: number = 0;

  /** The current sample rate, in Hz. */
  private sampleRate: number = 0;

  /** The current interleaved channel count. */
  private channels: number = 0;

  /** Clears sample continuity after listener or binding replacement. */
  reset(): void {
    this.anchorUs = undefined;
    this.samples = 0;
    this.sampleRate = 0;
    this.channels = 0;
  }

  /**
   * Resolves validated PCM, re-anchoring format changes or native clock differences over 100 ms.
   *
   * @param frame The owned PCM packet and provider-defined audio timestamp.
   */
  resolve(
    frame: RtcRemoteAudioFrame
  ): ResolvedRemoteAudioFrame {
    let timestampUs: number = this.anchorUs === undefined ? frame.timestampUs :
      this.anchorUs + this.samples * 1000000 / this.sampleRate;
    const discontinuous: boolean = this.anchorUs === undefined ||
      this.sampleRate !== frame.sampleRate || this.channels !== frame.channels ||
      Math.abs(frame.timestampUs - timestampUs) > 100000;
    if (discontinuous) {
      this.anchorUs = frame.timestampUs;
      this.samples = 0;
      this.sampleRate = frame.sampleRate;
      this.channels = frame.channels;
      timestampUs = frame.timestampUs;
    }

    this.samples += frame.samplesPerChannel;
    return new ResolvedRemoteAudioFrame(
      new RealtimeAudioFrame(
        frame.data,
        frame.sampleRate,
        frame.channels,
        frame.samplesPerChannel,
        timestampUs
      ),
      discontinuous
    );
  }
}
