import { fileIo } from '@kit.CoreFileKit';
import xmaxVideoNative, {
  NativeAudioFileDecoder
} from 'libxmax_video.so';
import { AudioFrame } from './AudioFrame';

/** 文件音频连续解码事件。 */
export interface AudioFileFrameDecoderListener {
  onFrame(frame: AudioFrame): void;
  onEndOfStream(): void;
  onError(message: string): void;
}

/** 使用系统音频解码器连续输出 48 kHz 单声道 PCM 帧。 */
export class AudioFileFrameDecoder {
  private readonly nativeDecoder: NativeAudioFileDecoder;
  private isReleased: boolean = false;

  constructor(
    filePath: string,
    playbackAnchorUs: number,
    mediaStartUs: number,
    cycleDurationUs: number,
    listener: AudioFileFrameDecoderListener
  ) {
    const sourceFile: fileIo.File = fileIo.openSync(
      filePath,
      fileIo.OpenMode.READ_ONLY
    );

    try {
      const sourceSize: number = fileIo.statSync(sourceFile.fd).size;
      this.nativeDecoder = xmaxVideoNative.createAudioFileDecoder(
        sourceFile.fd,
        sourceSize,
        playbackAnchorUs,
        mediaStartUs,
        cycleDurationUs,
        (
          data: ArrayBuffer | undefined,
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
            listener.onFrame(new AudioFrame(
              new Uint8Array(data),
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
