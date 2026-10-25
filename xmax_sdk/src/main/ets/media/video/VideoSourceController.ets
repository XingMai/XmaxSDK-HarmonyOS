//
//  VideoSourceController.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import {
  XmaxError,
  XmaxErrorCode
} from '../../foundation/errors/XmaxError';
import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import { BufferVideoFrame } from '../../foundation/media/video/BufferVideoFrame';
import {
  VideoFileDecodedFrame,
  VideoFileFrameDecoder,
  VideoFileFrameDecoderListener
} from '../../foundation/media/video/VideoFileFrameDecoder';
import { VideoFormat } from '../../foundation/media/video/VideoFormat';
import { VideoFramePlane } from '../../foundation/media/video/VideoFramePlane';
import { VideoRotation } from '../../foundation/media/video/VideoRotation';
import { MediaTimeline } from '../MediaTimeline';
import {
  VideoSourceControlling,
  VideoSourceErrorListener,
  VideoSourceFrameListener
} from './VideoSourceControlling';

const FRAME_INTERVAL_TOLERANCE: number = 0.75;

/**
 * The sampling interval is not a processing deadline; Surface access and scheduling may exceed one
 * frame.
 */

/** Allow up to three frame intervals, at least 100 ms, while discarding clearly stale frames. */
const MIN_FRAME_LATENESS_US: number = 100000;
const FRAME_LATENESS_INTERVALS: number = 3;

/** Decodes and samples file video on a shared timeline with optional looping. */
export class VideoSourceController implements VideoSourceControlling {

  // Frame and error notifications

  /** The receiver for prepared media frames. */
  private readonly frameListener: VideoSourceFrameListener;

  /** The handler for asynchronous component failures. */
  private readonly errorListener: VideoSourceErrorListener;

  // Decoder resources and release waits

  /** The native file decoder for the current playback cycle. */
  private decoder: VideoFileFrameDecoder | null = null;

  /** The pending decoder release awaited before replacement. */
  private decoderReleasePromise: Promise<void> | null = null;

  // File and source orientation configuration

  /** The local media file path. */
  private filePath: string = '';

  /** The rotation stored in the source file metadata. */
  private sourceRotation: VideoRotation = VideoRotation.ROTATION_0;

  // Loop playback timeline

  /** The playback timeline shared by audio and video. */
  private timeline: MediaTimeline | null = null;

  /** The zero-based playback cycle index. */
  private loopIndex: number = 0;

  // Decoded output format

  /** The target output frame interval, in microseconds. */
  private frameIntervalUs: number = 0;

  /** The decoded output width, in pixels. */
  private outputWidth: number = 0;

  /** The decoded output height, in pixels. */
  private outputHeight: number = 0;

  // Source timestamp deduplication

  /** The last accepted source timestamp, in microseconds. */
  private lastSourceTimestampUs: number = -1;

  // Pause, looping, and file completion state

  /** Whether media output is paused. */
  private isPaused: boolean = false;

  /** Whether completion arrived while playback was paused. */
  private pendingEndOfStream: boolean = false;

  /** Whether file playback restarts after natural completion. */
  private loop: boolean = true;

  /** Whether non-looping media output has ended naturally. */
  private hasEnded: boolean = false;

  // Video source revision and completion notification

  /** The revision rejecting output from obsolete file sources. */
  private sourceVersion: number = 0;

  /** Reports local media playback completion. */
  private readonly endedListener: () => void;

  /** Creates a video source controller. */
  constructor(
    frameListener: VideoSourceFrameListener,
    errorListener: VideoSourceErrorListener,
    endedListener: () => void = (): void => { }
  ) {
    this.frameListener = frameListener;
    this.errorListener = errorListener;
    this.endedListener = endedListener;
  }

  /**
   * Configures the video file, rotation, and target format.
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
    loop: boolean = true
  ): void {
    if (this.decoder !== null || this.decoderReleasePromise !== null) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Stop the current video source before configuring another file'
      );
    }

    this.filePath = filePath;
    this.loop = loop;
    this.sourceRotation = rotation;
    this.outputWidth = outputWidth;
    this.outputHeight = outputHeight;
    this.frameIntervalUs = 1000000 / frameRate;
    this.resetFrameSampling();
  }

  /**
   * Starts video output on the shared timeline.
   *
   * The Promise fulfills after background initialization and output startup.
   *
   * @param timeline The shared audio/video playback timeline.
   */
  async start(
    timeline: MediaTimeline
  ): Promise<void> {
    if (this.filePath.length === 0) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Configure the local media file before starting the video source'
      );
    }
    if (this.decoder !== null || this.decoderReleasePromise !== null) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Local video source is already active'
      );
    }

    this.timeline = timeline;
    this.sourceVersion++;
    this.hasEnded = false;
    this.loopIndex = 0;
    this.isPaused = false;
    this.pendingEndOfStream = false;
    this.resetFrameSampling();
    // Audio has not started yet. Exclude decoder setup time from both clocks.
    timeline.pause();
    await this.createDecoder(true);
  }

  /** Pauses the decoder while retaining media position and resources. */
  pause(): void {
    if (this.hasEnded) {
      return;
    }
    if (this.isPaused) {
      return;
    }
    const decoder: VideoFileFrameDecoder | null = this.decoder;
    if (decoder === null) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Local video source is not active'
      );
    }
    this.isPaused = true;
    decoder.pause();
  }

  /**
   * Resumes the decoder with the shared pause duration.
   *
   * @param pausedDurationUs The pause duration, in microseconds.
   */
  resume(
    pausedDurationUs: number
  ): void {
    if (this.hasEnded) {
      return;
    }
    if (!this.isPaused) {
      return;
    }
    const decoder: VideoFileFrameDecoder | null = this.decoder;
    if (decoder === null) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Local video source is not active'
      );
    }
    decoder.resume(pausedDurationUs);
    this.isPaused = false;
    if (this.pendingEndOfStream) {
      this.pendingEndOfStream = false;
      this.handleEndOfStream(this.loopIndex);
    }
  }

  /**
   * Stops output and clears video file state.
   *
   * The Promise fulfills after decoder release.
   */
  async stop(): Promise<void> {
    this.sourceVersion++;
    this.hasEnded = false;
    const releasePromise: Promise<void> = this.releaseDecoder();
    this.filePath = '';
    this.sourceRotation = VideoRotation.ROTATION_0;
    this.timeline = null;
    this.loopIndex = 0;
    this.isPaused = false;
    this.pendingEndOfStream = false;
    this.frameIntervalUs = 0;
    this.outputWidth = 0;
    this.outputHeight = 0;
    this.resetFrameSampling();
    await releasePromise;
  }

  /**
   * Creates a video frame decoder for the current file and timeline.
   *
   * The Promise fulfills after decoder readiness and shared-timeline activation.
   *
   * @param initial Whether this is initial startup; rebuilding for a loop preserves the shared
   * timeline.
   */
  private async createDecoder(
    initial: boolean = false
  ): Promise<void> {
    const timeline: MediaTimeline | null = this.timeline;
    if (timeline === null) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Video source timeline is unavailable'
      );
    }

    const loopIndex: number = this.loopIndex;
    const version: number = this.sourceVersion;
    const playbackAnchorUs: number = timeline.playbackAnchorForLoop(loopIndex);
    const decoder = new VideoFileFrameDecoder(
      this.filePath,
      this.sourceRotation,
      this.outputWidth,
      this.outputHeight,
      this.frameIntervalUs,
      new VideoSourceDecoderListener(
        (frame: VideoFileDecodedFrame): void => {
          if (version === this.sourceVersion && !this.hasEnded) {
            this.handleFrame(frame);
          }
        },
        (): void => {
          if (version === this.sourceVersion) {
            this.handleEndOfStream(loopIndex);
          }
        },
        (message: string): void => {
          if (version === this.sourceVersion) {
            this.errorListener(message);
          }
        }
      ),
      playbackAnchorUs,
      timeline.mediaStartUs,
      timeline.cycleDurationUs
    );
    this.decoder = decoder;
    await decoder.ready;
    if (version !== this.sourceVersion || this.decoder !== decoder) {
      await decoder.release();
      throw new XmaxError(
        XmaxErrorCode.CANCELLED,
        'Video initialization was cancelled'
      );
    }
    if (initial) {
      timeline.resume();
    }
    // Includes any pause/resume that happened while a loop decoder was loading.
    decoder.activate(timeline.playbackAnchorForLoop(loopIndex) - playbackAnchorUs);
  }

  /**
   * Delivers upright decoded frames that satisfy output sampling.
   *
   * @param frame The decoded file video frame.
   */
  private handleFrame(
    frame: VideoFileDecodedFrame
  ): void {
    if (this.isPaused || !this.shouldOutputFrame(frame)) {
      return;
    }

    const lumaLength: number = frame.width * frame.height;
    const videoFrame = new BufferVideoFrame(
      new VideoFormat(
        frame.width,
        frame.height,
        frame.pixelFormat
      ),
      frame.timestampUs,
      [
        new VideoFramePlane(
          frame.data,
          frame.stride,
          0,
          lumaLength
        ),
        new VideoFramePlane(
          frame.data,
          frame.stride,
          lumaLength,
          lumaLength / 2
        )
      ],
      VideoRotation.ROTATION_0
    );

    try {
      this.frameListener(videoFrame);
    } catch (error) {
      const reason: string = error instanceof Error ? error.message : String(error);
      this.errorListener(reason);
    }
  }

  /**
   * Creates the next video decoder after a playback cycle ends.
   *
   * @param loopIndex The completed decoder's playback cycle index.
   */
  private handleEndOfStream(
    loopIndex: number
  ): void {
    const endedDecoder: VideoFileFrameDecoder | null = this.decoder;
    if (endedDecoder === null || loopIndex !== this.loopIndex || this.hasEnded) {
      return;
    }
    if (this.isPaused) {
      this.pendingEndOfStream = true;
      return;
    }

    setTimeout(
      (): void => {
        void this.restartAfterEndOfStream(
          endedDecoder,
          loopIndex
        );
      },
      0
    );
  }

  /**
   * Releases the completed decoder asynchronously and starts the next cycle.
   *
   * The Promise fulfills after the next decoder is created.
   *
   * @param endedDecoder The decoder completing the current cycle.
   * @param loopIndex The completed cycle index.
   */
  private async restartAfterEndOfStream(
    endedDecoder: VideoFileFrameDecoder,
    loopIndex: number
  ): Promise<void> {
    if (this.decoder !== endedDecoder || loopIndex !== this.loopIndex) {
      return;
    }
    if (this.isPaused) {
      this.pendingEndOfStream = true;
      return;
    }
    const version: number = this.sourceVersion;
    if (!this.loop) {
      this.hasEnded = true;
      await this.releaseDecoder();
      if (version === this.sourceVersion) {
        this.endedListener();
      }
      return;
    }

    await this.releaseDecoder();
    if (version !== this.sourceVersion || this.decoder !== null || this.filePath.length === 0 ||
      this.timeline === null || loopIndex !== this.loopIndex) {
      return;
    }
    this.loopIndex++;
    this.resetFrameSampling();

    try {
      await this.createDecoder();
    } catch (error) {
      if (version === this.sourceVersion) {
        const reason: string = error instanceof Error ? error.message : String(error);
        this.errorListener(reason);
      }
    }
  }

  /**
   * Selects decoded frames using playback progress and target rate.
   *
   * @param frame The decoded file video frame.
   *
   * @returns True if the decoded frame should be output.
   */
  private shouldOutputFrame(
    frame: VideoFileDecodedFrame
  ): boolean {
    const nowUs: number = MediaTimeline.currentTimestampUs();
    const ageUs: number = nowUs - frame.timestampUs;
    const latenessLimitUs: number = Math.max(
      MIN_FRAME_LATENESS_US,
      this.frameIntervalUs * FRAME_LATENESS_INTERVALS
    );
    if (ageUs > latenessLimitUs) {
      return false;
    }

    const lastTimestampUs: number = this.lastSourceTimestampUs;
    if (lastTimestampUs >= 0 && frame.timestampUs - lastTimestampUs <
      this.frameIntervalUs * FRAME_INTERVAL_TOLERANCE) {
      return false;
    }

    this.lastSourceTimestampUs = frame.timestampUs;
    return true;
  }

  /** Resets video frame sampling progress. */
  private resetFrameSampling(): void {
    this.lastSourceTimestampUs = -1;
  }

  /**
   * Releases the current video decoder.
   *
   * The Promise fulfills after current decoder release.
   */
  private async releaseDecoder(): Promise<void> {
    const decoder: VideoFileFrameDecoder | null = this.decoder;
    this.decoder = null;
    const pendingRelease: Promise<void> | null = this.decoderReleasePromise;

    if (pendingRelease !== null) {
      await pendingRelease;
    }

    if (decoder !== null) {
      const releasePromise: Promise<void> =
        this.releaseDecoderInstance(decoder);
      this.decoderReleasePromise = releasePromise;
      try {
        await releasePromise;
      } finally {
        if (this.decoderReleasePromise === releasePromise) {
          this.decoderReleasePromise = null;
        }
      }
    }
  }

  /**
   * Releases a video decoder and logs release errors.
   *
   * The Promise fulfills after the specified decoder is released.
   *
   * @param decoder The video decoder to release.
   */
  private async releaseDecoderInstance(
    decoder: VideoFileFrameDecoder
  ): Promise<void> {
    try {
      await decoder.release();
    } catch (error) {
      const reason: string = error instanceof Error ? error.message : String(error);
      XmaxLogger.error(
        `${XmaxLogger.localized("释放本地视频解码器失败 (Failed to Release Local Video Decoder)\n└─ 原因：", "释放本地视频解码器失败 (Failed to Release Local Video Decoder)\n└─ Reason: ")}${reason}`,
        'Video'
      );
    }
  }
}

/** Forwards video decoder events to the source controller. */
class VideoSourceDecoderListener implements VideoFileFrameDecoderListener {

  /**
   * Delivers a decoded frame for the current source.
   *
   * @param frame The decoded video frame.
   */
  private readonly frameHandler: (
    frame: VideoFileDecodedFrame
  ) => void;

  /** Reports that the source reached the file end. */
  private readonly endHandler: () => void;

  /**
   * Delivers source decoding or output errors.
   *
   * @param message The local video decoding or output failure description.
   */
  private readonly errorHandler: (
    message: string
  ) => void;

  /** Creates a video decoder event adapter. */
  constructor(
    frameHandler: (
      frame: VideoFileDecodedFrame
    ) => void,
    endHandler: () => void,
    errorHandler: (
      message: string
    ) => void
  ) {
    this.frameHandler = frameHandler;
    this.endHandler = endHandler;
    this.errorHandler = errorHandler;
  }

  /**
   * Forwards decoded video frames.
   *
   * @param frame The decoded file video frame.
   */
  onFrame(
    frame: VideoFileDecodedFrame
  ): void {
    this.frameHandler(frame);
  }

  /** Forwards video completion. */
  onEndOfStream(): void {
    this.endHandler();
  }

  /**
   * Forwards video decoding errors.
   *
   * @param message The error message.
   */
  onError(
    message: string
  ): void {
    this.errorHandler(message);
  }
}
