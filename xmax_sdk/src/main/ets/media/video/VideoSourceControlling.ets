//
//  VideoSourceControlling.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { VideoRotation } from '../../foundation/media/video/VideoRotation';
import { VideoFrame } from '../../foundation/media/video/VideoFrame';
import { MediaTimeline } from '../MediaTimeline';

/**
 * Receives local video frames on the playback timeline.
 *
 * @param frame The oriented file video frame sampled for the configured output frame rate.
 */
export type VideoSourceFrameListener = (
  frame: VideoFrame
) => void;

/**
 * Receives local video configuration or decoding errors.
 *
 * @param message The local video configuration or decoding failure description.
 */
export type VideoSourceErrorListener = (
  message: string
) => void;

/** An interface for local file video output. */
export interface VideoSourceControlling {

  /**
   * Configures the video track for output.
   *
   * Stop the current decoder and await its release before reconfiguring this source.
   *
   * @param filePath The local video file path.
   * @param rotation The video source rotation.
   * @param outputWidth The target video width.
   * @param outputHeight The target video height.
   * @param frameRate The target video frame rate.
   * @param loop Whether to loop after file completion.
   *
   * @throws A configuration error if a decoder is active or still being released.
   */
  configure(
    filePath: string,
    rotation: VideoRotation,
    outputWidth: number,
    outputHeight: number,
    frameRate: number,
    loop?: boolean
  ): void;

  /**
   * Starts video output on the shared timeline.
   *
   * The Promise fulfills after background initialization and output startup.
   *
   * @param timeline The shared audio/video playback timeline.
   */
  start(
    timeline: MediaTimeline
  ): Promise<void>;

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

  /**
   * Stops output and releases video file resources.
   *
   * The Promise fulfills after video file resources are released.
   */
  stop(): Promise<void>;
}
