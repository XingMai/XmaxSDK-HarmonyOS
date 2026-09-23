import { fileIo } from '@kit.CoreFileKit';
import xmaxVideoNative, {
  NativeVideoFileDecoder
} from 'libxmax_video.so';
import { VideoPixelFormat } from './VideoPixelFormat';
import { VideoRotation } from './VideoRotation';

/** 系统视频解码器连续输出的单个文件视频帧。 */
export class VideoFileDecodedFrame {
  readonly data: ArrayBuffer;
  readonly width: number;
  readonly height: number;
  readonly stride: number;
  readonly timestampUs: number;
  readonly pixelFormat: VideoPixelFormat;

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

/** 文件视频连续解码事件。 */
export interface VideoFileFrameDecoderListener {
  onFrame(frame: VideoFileDecodedFrame): void;
  onEndOfStream(): void;
  onError(message: string): void;
}

/**
 * 使用系统视频解码器按媒体时间戳连续输出已转正的 NV12 帧。
 *
 * 解码结果由媒体层转换为统一视频帧，并交由后续业务链路处理。
 */
export class VideoFileFrameDecoder {
  readonly ready: Promise<void>;
  private nativeDecoder: NativeVideoFileDecoder | null = null;
  private isReleased: boolean = false;
  private releasePromise: Promise<void> | null = null;
  private isActivated: boolean = false;
  private isPaused: boolean = false;
  private activationOffsetUs: number = 0;

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
    this.ready = this.initialize(videoUri, rotation, outputWidth, outputHeight,
      frameIntervalUs, listener, playbackAnchorUs, mediaStartUs, cycleDurationUs);
  }

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

  /** 就绪后一次性放行；正在暂停时保留校准量，等待恢复。 */
  activate(anchorOffsetUs: number): void {
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

  pause(): void {
    this.isPaused = true;
    if (!this.isReleased && this.isActivated && this.nativeDecoder !== null) {
      this.nativeDecoder.pause();
    }
  }

  resume(pausedDurationUs: number): void {
    this.isPaused = false;
    if (!this.isReleased && this.isActivated && this.nativeDecoder !== null) {
      this.nativeDecoder.resume(this.activationOffsetUs + pausedDurationUs);
      this.activationOffsetUs = 0;
    }
  }

  release(): Promise<void> {
    if (this.releasePromise === null) {
      this.isReleased = true;
      this.releasePromise = this.releaseWhenReady();
    }
    return this.releasePromise;
  }

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
