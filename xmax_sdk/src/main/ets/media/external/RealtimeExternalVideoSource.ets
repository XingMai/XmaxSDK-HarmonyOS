//
//  RealtimeExternalVideoSource.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import { RealtimeVideoFrame } from '../../service/realtime/RealtimeVideoFrame';
import { RealtimeAudioFrame } from '../../service/realtime/RealtimeMediaFrame';

/**
 * A video source captured, decoded, or processed by your app, with optional PCM audio.
 *
 * Your app owns permissions, devices, playback, and resource cleanup. Keep videoFormat and hasAudio
 * unchanged while bound. Lifecycle and sink calls belong to the manager's ArkTS environment;
 * forward Worker output through messages rather than sharing the sink across environments.
 */
export interface RealtimeExternalVideoSource {

  /** Source dimensions, FPS, and encoding settings; at most 32768 per dimension and 16777216 pixels. */
  readonly videoFormat: RealtimeVideoFormat;

  /** Whether the source supplies PCM for upload; defaults to false, without local playback. */
  readonly hasAudio?: boolean;

  /**
   * Installs the producer callback and returns when ready, without waiting for the first frame.
   * Continue supplying preview frames before generation and after disconnect.
   *
   * @param sink The receiver for this binding; never retain a sink from a previous binding.
   */
  start(
    sink: RealtimeExternalFrameSink
  ): Promise<void>;

  /** Stops frame callbacks and releases the sink reference; must be safe to call repeatedly. */
  stop(): Promise<void>;
}

/** A synchronous receiver scoped to one external source binding. */
export interface RealtimeExternalFrameSink {

  /** The processed local dimensions after model pixel limits and four-pixel alignment. */
  readonly videoFormat: RealtimeVideoFormat;

  /** True while bound, including disconnected preview; permanently false after stop or failure. */
  readonly isRequestingFrames: boolean;

  /**
   * Copies or resizes upright NV12 video-range or BGRA pixels before returning.
   * Dimensions must match source.videoFormat; apply rotation and mirroring to pixels beforehand.
   * Buffers can be reused afterward. Invalid, duplicate, and decreasing timestamps are ignored.
   *
   * @param frame The source pixels with a nonnegative monotonic timestamp in microseconds.
   */
  pushVideo(
    frame: RealtimeVideoFrame
  ): void;

  /**
   * Copies interleaved signed little-endian PCM16 and converts to 48 kHz mono 10 ms packets.
   * Keep sample rate and channel count fixed. Audio and video use the same monotonic timeline.
   * Invalid timestamps and overlapping buffers are ignored; gaps begin a segment without silence.
   * Only published audio is uploaded; no reconnect queue or local playback is provided.
   *
   * @param frame Ready PCM samples; compressed audio must be decoded before submission.
   */
  pushAudio(
    frame: RealtimeAudioFrame
  ): void;

  /**
   * Permanently invalidates this sink and reports an unrecoverable source failure.
   *
   * @param error The capture, decoding, or processing failure ending this source.
   */
  reportError(
    error: Error
  ): void;
}
