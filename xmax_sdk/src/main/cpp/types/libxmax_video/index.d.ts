type NativeVideoFileFrameListener = (
  data: ArrayBuffer | undefined,
  width: number,
  height: number,
  stride: number,
  timestampUs: number,
  endOfStream: boolean,
  error?: string
) => void;

export interface NativeVideoFileDecoder {
  /** 停止连续解码并释放文件、解封装器与解码器资源。 */
  release(): Promise<void>;
}

type NativeAudioFileFrameListener = (
  data: ArrayBuffer | undefined,
  timestampUs: number,
  endOfStream: boolean,
  error?: string
) => void;

export interface NativeAudioFileDecoder {
  /** 停止连续解码并释放文件、解封装器与解码器资源。 */
  release(): void;
}

interface XmaxVideoNative {
  /** 使用系统视频解码器按媒体时间戳连续输出已转正的 NV12 帧。 */
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
  ): NativeVideoFileDecoder;

  /** 使用系统音频解码器连续输出 48 kHz 单声道 PCM 帧。 */
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
