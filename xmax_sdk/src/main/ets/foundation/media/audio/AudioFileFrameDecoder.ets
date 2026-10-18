//
//  AudioFileFrameDecoder.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { fileIo } from '@kit.CoreFileKit';
import xmaxVideoNative, {
  NativeAudioFileDecoder
} from 'libxmax_video.so';
import { AudioFrame } from './AudioFrame';

/** 文件音频连续解码事件。 */
export interface AudioFileFrameDecoderListener {
  /**
   * 接收按媒体时间轴输出的解码帧。
   *
   * @param frame 解码后的音频帧。
   * @returns 无返回值。
   */
  onFrame(frame: AudioFrame): void;

  /**
   * 通知当前文件的解码输出已经结束。
   *
   * @returns 无返回值。
   */
  onEndOfStream(): void;

  /**
   * 通知解码或帧输出失败的原因。
   *
   * @param message 错误信息。
   * @returns 无返回值。
   */
  onError(message: string): void;
}

/** 使用系统音频解码器连续输出 48 kHz 单声道 PCM 帧。 */
export class AudioFileFrameDecoder {

  /** 原生音频解码资源与释放状态 */
  private readonly nativeDecoder: NativeAudioFileDecoder;
  private isReleased: boolean = false;

  /**
   * 创建音频文件解码器。
   *
   * @param filePath 本地媒体文件路径。
   * @param playbackAnchorUs 媒体起点对应的单调播放时间，单位微秒。
   * @param mediaStartUs 媒体时间轴的起始时间，单位微秒。
   * @param cycleDurationUs 单轮媒体播放时长，单位微秒。
   * @param listener 接收媒体帧与解码状态的监听器。
   * @returns 新建的 AudioFileFrameDecoder 实例。
   */
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

  /**
   * 暂停音频文件的连续解码输出。
   *
   * @returns 无返回值。
   */
  pause(): void {
    if (!this.isReleased) {
      this.nativeDecoder.pause();
    }
  }

  /**
   * 恢复音频解码，并按暂停时长平移播放锚点。
   *
   * @param pausedDurationUs 本次暂停持续时间，单位微秒。
   * @returns 无返回值。
   */
  resume(pausedDurationUs: number): void {
    if (!this.isReleased) {
      this.nativeDecoder.resume(pausedDurationUs);
    }
  }

  /**
   * 停止音频解码回调并释放原生解码器资源。
   *
   * @returns 无返回值。
   */
  release(): void {
    if (this.isReleased) {
      return;
    }

    this.isReleased = true;
    this.nativeDecoder.release();
  }
}
