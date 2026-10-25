//
//  VideoFileFrameDecoder.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { fileIo } from '@kit.CoreFileKit';
import xmaxVideoNative, {
  NativeVideoFileDecoder
} from 'libxmax_video.so';
import { VideoPixelFormat } from './VideoPixelFormat';
import { VideoRotation } from './VideoRotation';

/** A decoded file video frame from the system decoder. */
export class VideoFileDecodedFrame {

  // Decoded pixels and frame layout

  /** The decoded NV12 frame pixels. */
  readonly data: ArrayBuffer;

  /** The decoded width, in pixels. */
  readonly width: number;

  /** The decoded height, in pixels. */
  readonly height: number;

  /** The plane row stride, in bytes. */
  readonly stride: number;

  /** The frame timestamp, in microseconds. */
  readonly timestampUs: number;

  /** The pixel layout used by the frame buffer. */
  readonly pixelFormat: VideoPixelFormat;

  /**
   * Creates a native decoded video frame.
   *
   * @param data The decoded NV12 pixel buffer, retained without copying.
   * @param width The frame width, in pixels.
   * @param height The frame height, in pixels.
   * @param stride The image row stride, in bytes.
   * @param timestampUs The media frame timestamp, in microseconds.
   */
  constructor(
    data: ArrayBuffer,
    width: number,
    height: number,
    stride: number,
    timestampUs: number
  ) {
    this.data = data;
    this.width = width;
    this.height = height;
    this.stride = stride;
    this.timestampUs = timestampUs;
    this.pixelFormat = VideoPixelFormat.NV12;
  }
}

/** Continuous video file decoding events. */
export interface VideoFileFrameDecoderListener {

  /**
   * Receives decoded frames on the media timeline.
   *
   * @param frame The decoded NV12 video frame with its media timestamp.
   */
  onFrame(
    frame: VideoFileDecodedFrame
  ): void;

  /** Reports completion of the current file's decoded output. */
  onEndOfStream(): void;

  /**
   * Reports a decoding or frame delivery failure.
   *
   * @param message The error message.
   */
  onError(
    message: string
  ): void;
}

/**
 * Decodes upright NV12 frames paced by media timestamps through the system decoder. The media layer
 * converts output into neutral video frames for subsequent processing.
 */
export class VideoFileFrameDecoder {

  // Decoder initialization and native resources

  /** The Promise tracking native decoder initialization. */
  readonly ready: Promise<void>;

  /** The native file decoder owned by this wrapper. */
  private nativeDecoder: NativeVideoFileDecoder | null = null;

  // Release state and pending asynchronous release

  /** Whether the owned resource has been released. */
  private isReleased: boolean = false;

  /** The shared Promise for pending native resource release. */
  private releasePromise: Promise<void> | null = null;

  // Output activation and pause state

  /** Whether decoded output has been activated on the shared timeline. */
  private isActivated: boolean = false;

  /** Whether media output is paused. */
  private isPaused: boolean = false;

  /** The pending playback anchor adjustment, in microseconds. */
  private activationOffsetUs: number = 0;

  /**
   * Creates a video file decoder.
   *
   * @param videoUri The local video file URI to decode.
   * @param rotation The rotation to apply to the video image.
   * @param outputWidth The decoded output width, in pixels.
   * @param outputHeight The decoded output height, in pixels.
   * @param frameIntervalUs The video output interval, in microseconds.
   * @param listener The handler for decoded NV12 frames, file completion, and decoding failures.
   * @param playbackAnchorUs The monotonic playback time for the media origin, in microseconds.
   * @param mediaStartUs The media timeline origin, in microseconds.
   * @param cycleDurationUs The playback cycle duration, in microseconds.
   */
  constructor(
    videoUri: string,
    rotation: VideoRotation,
    outputWidth: number,
    outputHeight: number,
    frameIntervalUs: number,
    listener: VideoFileFrameDecoderListener,
    playbackAnchorUs: number,
    mediaStartUs: number,
    cycleDurationUs: number
  ) {
    this.ready = this.initialize(
      videoUri,
      rotation,
      outputWidth,
      outputHeight,
      frameIntervalUs,
      listener,
      playbackAnchorUs,
      mediaStartUs,
      cycleDurationUs
    );
  }

  /**
   * Creates a video file decoder asynchronously and applies pending activation or pause state.
   *
   * @param videoUri The local video file URI to decode.
   * @param rotation The rotation to apply to the video image.
   * @param outputWidth The decoded output width, in pixels.
   * @param outputHeight The decoded output height, in pixels.
   * @param frameIntervalUs The video output interval, in microseconds.
   * @param listener The handler for decoded NV12 frames, file completion, and decoding failures.
   * @param playbackAnchorUs The monotonic playback time for the media origin, in microseconds.
   * @param mediaStartUs The media timeline origin, in microseconds.
   * @param cycleDurationUs The playback cycle duration, in microseconds.
   */
  private async initialize(
    videoUri: string,
    rotation: VideoRotation,
    outputWidth: number,
    outputHeight: number,
    frameIntervalUs: number,
    listener: VideoFileFrameDecoderListener,
    playbackAnchorUs: number,
    mediaStartUs: number,
    cycleDurationUs: number
  ): Promise<void> {
    const sourceFile: fileIo.File = await fileIo.open(
      videoUri,
      fileIo.OpenMode.READ_ONLY
    );
    try {
      if (this.isReleased) {
        return;
      }
      const sourceSize: number = (await fileIo.stat(sourceFile.fd)).size;
      if (this.isReleased) {
        return;
      }
      this.nativeDecoder = await xmaxVideoNative.createVideoFileDecoder(
        sourceFile.fd,
        sourceSize,
        playbackAnchorUs,
        mediaStartUs,
        rotation,
        outputWidth,
        outputHeight,
        frameIntervalUs,
        cycleDurationUs,
        (
          data: ArrayBuffer | undefined,
          width: number,
          height: number,
          stride: number,
          timestampUs: number,
          endOfStream: boolean,
          error?: string
        ): void => {
          if (this.isReleased) {
            return;
          }
          if (error !== undefined && error.length > 0) {
            listener.onError(error);
            return;
          }
          if (endOfStream) {
            listener.onEndOfStream();
            return;
          }
          if (data !== undefined) {
            listener.onFrame(new VideoFileDecodedFrame(
              data,
              width,
              height,
              stride,
              timestampUs
            ));
          }
        }
      );
    } finally {
      // Native duplicates the fd before scheduling initialization.
      await fileIo.close(sourceFile);
    }
  }

  /**
   * Activate output once ready; while paused, retain the anchor adjustment until resume.
   *
   * @param anchorOffsetUs The offset from the playback anchor, in microseconds.
   */
  activate(
    anchorOffsetUs: number
  ): void {
    if (this.isReleased || this.isActivated || this.nativeDecoder === null) {
      return;
    }
    this.isActivated = true;
    this.activationOffsetUs = anchorOffsetUs;
    if (!this.isPaused) {
      this.nativeDecoder.resume(this.activationOffsetUs);
      this.activationOffsetUs = 0;
    }
  }

  /** Pauses continuous video file decoding. */
  pause(): void {
    this.isPaused = true;
    if (!this.isReleased && this.isActivated && this.nativeDecoder !== null) {
      this.nativeDecoder.pause();
    }
  }

  /**
   * Resumes video decoding with the playback anchor shifted by the pause duration.
   *
   * @param pausedDurationUs The pause duration, in microseconds.
   */
  resume(
    pausedDurationUs: number
  ): void {
    this.isPaused = false;
    if (!this.isReleased && this.isActivated && this.nativeDecoder !== null) {
      this.nativeDecoder.resume(this.activationOffsetUs + pausedDurationUs);
      this.activationOffsetUs = 0;
    }
  }

  /** Stops video output and waits for native resource release. */
  release(): Promise<void> {
    if (this.releasePromise === null) {
      this.isReleased = true;
      this.releasePromise = this.releaseWhenReady();
    }
    return this.releasePromise;
  }

  /** Waits for decoder creation before releasing native resources. */
  private async releaseWhenReady(): Promise<void> {
    try {
      await this.ready;
    } catch (_) {
      // Native initialization failures already clean up on the worker thread.
    }
    const decoder: NativeVideoFileDecoder | null = this.nativeDecoder;
    this.nativeDecoder = null;
    if (decoder !== null) {
      await decoder.release();
    }
  }
}
