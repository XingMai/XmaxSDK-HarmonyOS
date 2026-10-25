//
//  ExternalVideoFrameSink.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import xmaxVideoNative from 'libxmax_video.so';
import { XmaxError, XmaxErrorCode } from '../../foundation/errors/XmaxError';
import { AudioFrame } from '../../foundation/media/audio/AudioFrame';
import { BufferVideoFrame } from '../../foundation/media/video/BufferVideoFrame';
import { VideoFrame } from '../../foundation/media/video/VideoFrame';
import { VideoFormat } from '../../foundation/media/video/VideoFormat';
import { VideoFramePlane } from '../../foundation/media/video/VideoFramePlane';
import { VideoPixelFormat } from '../../foundation/media/video/VideoPixelFormat';
import { VideoRotation } from '../../foundation/media/video/VideoRotation';
import { RealtimeAudioFrame } from '../../service/realtime/RealtimeMediaFrame';
import { RealtimeVideoFrame } from '../../foundation/media/video/RealtimeVideoFrame';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import { ExternalAudioFrameConverter } from './ExternalAudioFrameConverter';
import { RealtimeExternalFrameSink } from './RealtimeExternalVideoSource';

/** A synchronous external frame sink permanently invalidated on detach or failure. */
export class ExternalVideoFrameSink implements RealtimeExternalFrameSink {

  /** The resolved local preview and uplink format. */
  readonly videoFormat: RealtimeVideoFormat;

  /** The immutable source dimensions declared at binding. */
  private readonly sourceVideoFormat: RealtimeVideoFormat;

  /** Receives processed video on the manager's ArkTS environment. */
  private readonly videoListener: (
    frame: VideoFrame
  ) => void;

  /** Receives packetized audio without local playback. */
  private readonly audioListener: (
    frame: AudioFrame
  ) => void;

  /** Reports the binding's first unrecoverable error. */
  private readonly errorListener: (
    error: XmaxError
  ) => void;

  /** Whether frames and failures still belong to this binding. */
  private active: boolean = true;

  /** The last accepted video timestamp, in microseconds. */
  private lastVideoUs: number = -1;

  /** The optional PCM converter, released on invalidation. */
  private audioConverter: ExternalAudioFrameConverter | null;

  /** Creates a sink with immutable source and resolved output formats. */
  constructor(
    sourceVideoFormat: RealtimeVideoFormat,
    videoFormat: RealtimeVideoFormat,
    hasAudio: boolean,
    videoListener: (
      frame: VideoFrame
    ) => void,
    audioListener: (
      frame: AudioFrame
    ) => void,
    errorListener: (
      error: XmaxError
    ) => void
  ) {
    this.sourceVideoFormat = sourceVideoFormat;
    this.videoFormat = videoFormat;
    this.audioConverter = hasAudio ? new ExternalAudioFrameConverter() : null;
    this.videoListener = videoListener;
    this.audioListener = audioListener;
    this.errorListener = errorListener;
  }

  /** True while the binding accepts preview and generation frames. */
  get isRequestingFrames(): boolean {
    return this.active;
  }

  /**
   * Copies source pixels synchronously and shares the processed frame with preview and uplink.
   *
   * @param frame Upright NV12 video-range or BGRA pixels matching the declared source dimensions.
   */
  pushVideo(
    frame: RealtimeVideoFrame
  ): void {
    if (!this.active || !Number.isFinite(frame.timestampUs) ||
      frame.timestampUs < 0 || frame.timestampUs <= this.lastVideoUs) {
      return;
    }

    try {
      if (frame.width !== this.sourceVideoFormat.width || frame.height !== this.sourceVideoFormat.height ||
        frame.rotation !== VideoRotation.ROTATION_0 ||
        (frame.pixelFormat !== VideoPixelFormat.NV12 && frame.pixelFormat !== VideoPixelFormat.BGRA)) {
        throw new XmaxError(
          XmaxErrorCode.MEDIA_ERROR,
          'External video requires upright NV12 or BGRA pixels matching source.videoFormat'
        );
      }

      const data: ArrayBuffer = xmaxVideoNative.convertExternalVideoFrame(
        frame,
        this.videoFormat.width,
        this.videoFormat.height
      );
      const width: number = this.videoFormat.width;
      const height: number = this.videoFormat.height;
      const ySize: number = width * height;
      const output = new BufferVideoFrame(
        new VideoFormat(
          width,
          height,
          VideoPixelFormat.NV12
        ),
        frame.timestampUs,
        [
          new VideoFramePlane(
            data,
            width,
            0,
            ySize
          ),
          new VideoFramePlane(
            data,
            width,
            ySize,
            ySize / 2
          )
        ]
      );
      this.lastVideoUs = frame.timestampUs;
      this.videoListener(output);
    } catch (error) {
      this.reportError(new Error(XmaxError.from(error).message));
    }
  }

  /**
   * Converts PCM only when the source opted into external audio.
   *
   * @param frame Ready interleaved PCM16 samples on the shared audio/video timeline.
   */
  pushAudio(
    frame: RealtimeAudioFrame
  ): void {
    if (!this.active || this.audioConverter === null) {
      return;
    }

    try {
      this.audioConverter.append(
        frame,
        (output: AudioFrame): void => {
        if (this.active) {
          this.audioListener(output);
        }
      }
      );
    } catch (error) {
      this.reportError(new Error(XmaxError.from(error).message));
    }
  }

  /**
   * Invalidates both inputs and reports one fatal source failure.
   *
   * @param error The unrecoverable capture, conversion, or delivery failure.
   */
  reportError(
    error: Error
  ): void {
    if (!this.active) {
      return;
    }

    this.invalidate();
    this.errorListener(new XmaxError(
      XmaxErrorCode.MEDIA_ERROR,
      'External video source failed: ' + error.message
    ));
  }

  /** Rejects subsequent frames and releases partial audio without forwarding or padding it. */
  invalidate(): void {
    this.active = false;
    this.audioConverter = null;
  }
}
