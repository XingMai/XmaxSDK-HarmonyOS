//
//  index.d.ts
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/**
 * Receives decoded video, file completion, or a decoding error.
 *
 * @param data The decoded NV12 pixel buffer, or undefined for a completion or error event.
 * @param width The frame width, in pixels.
 * @param height The frame height, in pixels.
 * @param stride The image row stride, in bytes.
 * @param timestampUs The media frame timestamp, in microseconds.
 * @param endOfStream Whether the file has reached its end.
 * @param error The video decoding failure description, when present.
 */
type NativeVideoFileFrameListener = (
  data: ArrayBuffer | undefined,
  width: number,
  height: number,
  stride: number,
  timestampUs: number,
  endOfStream: boolean,
  error?: string
) => void;

/** Controls native video decoding, playback, and asynchronous release. */
export interface NativeVideoFileDecoder {

  /** Pauses decoded output on the media timeline. */
  pause(): void;

  /**
   * Resumes decoding with the playback anchor shifted by the pause duration.
   *
   * @param pausedDurationUs The pause duration, in microseconds.
   */
  resume(
    pausedDurationUs: number
  ): void;

  /** Stops decoding and releases the file, demuxer, and decoder. */
  release(): Promise<void>;
}

/**
 * Receives decoded PCM, file completion, or an error.
 *
 * @param data The decoded 48 kHz mono signed 16-bit PCM buffer, or undefined for completion or
 * failure.
 * @param timestampUs The media frame timestamp, in microseconds.
 * @param endOfStream Whether the file has reached its end.
 * @param error The audio decoding failure description, when present.
 */
type NativeAudioFileFrameListener = (
  data: ArrayBuffer | undefined,
  timestampUs: number,
  endOfStream: boolean,
  error?: string
) => void;

/** Controls native audio decoding, playback, and resource release. */
export interface NativeAudioFileDecoder {

  /** Pauses decoded output on the media timeline. */
  pause(): void;

  /**
   * Resumes decoding with the playback anchor shifted by the pause duration.
   *
   * @param pausedDurationUs The pause duration, in microseconds.
   */
  resume(
    pausedDurationUs: number
  ): void;

  /** Stops decoding and releases the file, demuxer, and decoder. */
  release(): void;
}

/**
 * Receives converted camera NV12 data or a processing error.
 *
 * @param data The converted NV12 pixel buffer, or undefined when no camera frame is available.
 * @param width The frame width, in pixels.
 * @param height The frame height, in pixels.
 * @param timestampUs The media frame timestamp, in microseconds.
 * @param error The camera frame processing failure description, when present.
 */
type NativeCameraFrameListener = (
  data: ArrayBuffer | undefined,
  width: number,
  height: number,
  timestampUs: number,
  error?: string
) => void;

/** Receives raw CameraKit frames and outputs the configured size, rotation, and frame rate. */
export interface NativeFrameReceiver {

  /**
   * Returns the native receiving Surface for CameraKit output binding.
   *
   * @returns The native Surface identifier for CameraKit output creation.
   */
  getSurfaceId(): string;

  /**
   * Configures output dimensions, rotation, and frame rate.
   *
   * @param width The frame width, in pixels.
   * @param height The frame height, in pixels.
   * @param rotation The rotation to apply to the video image.
   * @param frameRate The target video frame rate, in fps.
   * @param captureFrameRate The capture frame rate, in fps.
   */
  configure(
    width: number,
    height: number,
    rotation: number,
    frameRate: number,
    captureFrameRate: number
  ): void;

  /** Stops frame callbacks and releases native image receiving resources. */
  release(): void;
}

/** Controls PCM admission while retaining the native observer until its engine lease ends. */
export interface NativeRtcRemoteAudioObserver {

  /** Invalidates queued PCM when observation is disabled or begins a new binding. */
  setEnabled(
    enabled: boolean
  ): void;

  /** Detaches the native observer before the engine is destroyed; safe to repeat. */
  close(): void;
}

/** Receives owned PCM with the original native audio timestamp and queue-loss information. */
type NativeRtcRemoteAudioListener = (
  roomId: string,
  userId: string,
  streamIndex: number,
  data: ArrayBuffer,
  sampleRate: number,
  channels: number,
  timestampUs: number,
  isDiscontinuous: boolean
) => void;

/** ArkTS bridges for native camera receiving, RTC PCM, and audio/video file decoding. */
interface XmaxVideoNative {

  /** Registers unmixed PCM observation using the opaque native handle of the leased RTC engine. */
  createRtcRemoteAudioObserver(
    engineHandle: Object | number | bigint,
    listener: NativeRtcRemoteAudioListener
  ): NativeRtcRemoteAudioObserver;

  /** Copies or scales upright NV12 or BGRA source planes into owned tightly packed NV12. */
  convertExternalVideoFrame(
    frame: object,
    outputWidth: number,
    outputHeight: number
  ): ArrayBuffer;

  /**
   * Creates a raw CameraKit frame receiver.
   *
   * @param sourceWidth The raw camera frame width, in pixels.
   * @param sourceHeight The raw camera frame height, in pixels.
   * @param listener The handler for converted NV12 camera frames and processing failures.
   *
   * @returns The native receiver for CameraKit output binding.
   */
  createFrameReceiver(
    sourceWidth: number,
    sourceHeight: number,
    listener: NativeCameraFrameListener
  ): NativeFrameReceiver;

  /**
   * Initializes a paused system decoder on a worker; call resume to start output.
   *
   * @param fd The open local file descriptor.
   * @param size The local media file length, in bytes.
   * @param playbackAnchorUs The monotonic playback time for the media origin, in microseconds.
   * @param mediaStartUs The media timeline origin, in microseconds.
   * @param rotation The rotation to apply to the video image.
   * @param outputWidth The decoded output width, in pixels.
   * @param outputHeight The decoded output height, in pixels.
   * @param frameIntervalUs The video output interval, in microseconds.
   * @param cycleDurationUs The playback cycle duration, in microseconds.
   * @param listener The handler for decoded NV12 frames, file completion, and decoding failures.
   *
   * @returns The initialized, paused native decoder; call resume to start output.
   */
  createVideoFileDecoder(
    fd: number,
    size: number,
    playbackAnchorUs: number,
    mediaStartUs: number,
    rotation: number,
    outputWidth: number,
    outputHeight: number,
    frameIntervalUs: number,
    cycleDurationUs: number,
    listener: NativeVideoFileFrameListener
  ): Promise<NativeVideoFileDecoder>;

  /**
   * Decodes continuous audio into 48 kHz mono PCM frames.
   *
   * @param fd The open local file descriptor.
   * @param size The local media file length, in bytes.
   * @param playbackAnchorUs The monotonic playback time for the media origin, in microseconds.
   * @param mediaStartUs The media timeline origin, in microseconds.
   * @param cycleDurationUs The playback cycle duration, in microseconds.
   * @param listener The handler for decoded PCM packets, file completion, and decoding failures.
   *
   * @returns The native decoder delivering PCM on the playback timeline.
   */
  createAudioFileDecoder(
    fd: number,
    size: number,
    playbackAnchorUs: number,
    mediaStartUs: number,
    cycleDurationUs: number,
    listener: NativeAudioFileFrameListener
  ): NativeAudioFileDecoder;
}

declare const xmaxVideoNative: XmaxVideoNative;
export default xmaxVideoNative;
