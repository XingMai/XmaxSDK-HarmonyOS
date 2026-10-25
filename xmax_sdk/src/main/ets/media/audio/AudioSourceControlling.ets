//
//  AudioSourceControlling.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { MediaTimeline } from '../MediaTimeline';

/** An interface for local file audio output. */
export interface AudioSourceControlling {

  /**
   * Configures the local file for output.
   *
   * @param filePath The local media file path.
   * @param loop Whether to loop after file completion.
   */
  configure(
    filePath: string,
    loop?: boolean
  ): void;

  /**
   * Starts audio frame output on the shared timeline.
   *
   * @param timeline The shared audio/video playback timeline.
   */
  start(
    timeline: MediaTimeline
  ): void;

  /** Pauses the decoder while retaining media position and resources. */
  pause(): void;

  /**
   * Resumes the decoder with the shared pause duration.
   *
   * @param pausedDurationUs The pause duration, in microseconds.
   */
  resume(
    pausedDurationUs: number
  ): void;

  /** Stops output and releases audio decoding resources. */
  stop(): void;
}
