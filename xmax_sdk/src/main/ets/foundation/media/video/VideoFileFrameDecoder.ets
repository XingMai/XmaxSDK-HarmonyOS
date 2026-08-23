import { fileIo } from '@kit.CoreFileKit';
import systemDateTime from '@ohos.systemDateTime';
import xmaxVideoNative, {
  NativeVideoFileDecoder
} from 'libxmax_video.so';
import { VideoPixelFormat } from './VideoPixelFormat';

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
 * 使用系统视频解码器按媒体时间戳连续输出 NV12 帧。
 *
 * 解码结果由媒体层转换为统一视频帧，并交由后续业务链路处理。
 */
export class VideoFileFrameDecoder {
  private readonly nativeDecoder: NativeVideoFileDecoder;
  private isReleased: boolean = false;

  constructor(
    videoUri: string,
    listener: VideoFileFrameDecoderListener,
    playbackAnchorUs?: number,
    mediaStartUs?: number
  ) {
    const resolvedPlaybackAnchorUs: number = playbackAnchorUs ??
      systemDateTime.getUptime(
        systemDateTime.TimeType.ACTIVE,
        true
      ) / 1000;
    const resolvedMediaStartUs: number = mediaStartUs ?? 0;

    const sourceFile: fileIo.File = fileIo.openSync(
      videoUri,
      fileIo.OpenMode.READ_ONLY
    );
    try {
      const sourceSize: number = fileIo.statSync(sourceFile.fd).size;
      this.nativeDecoder = xmaxVideoNative.createVideoFileDecoder(
        sourceFile.fd,
        sourceSize,
        resolvedPlaybackAnchorUs,
        resolvedMediaStartUs,
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
      fileIo.closeSync(sourceFile);
    }
  }

  release(): void {
    if (this.isReleased) {
      return;
    }
    this.isReleased = true;
    this.nativeDecoder.release();
  }
}
