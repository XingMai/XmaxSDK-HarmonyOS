import { audio } from '@kit.AudioKit';
import { XmaxLogger } from '../../logging/XmaxLogger';
import { AudioFrame } from './AudioFrame';
import { AudioManaging } from './AudioManaging';

/** 使用平台音频渲染器播放本地 PCM 音频帧。 */
export class AudioManager implements AudioManaging {

  // 平台资源
  private renderer: audio.AudioRenderer | null = null;

  // 音频缓冲
  private pendingFrames: Uint8Array[] = [];
  private pendingFrameOffset: number = 0;
  private isPlaybackEnabled: boolean = true;

  /**
   * 创建并启动本地 PCM 音频播放器。
   *
   * @returns 播放器启动完成后的 Promise。
   */
  async start(): Promise<void> {
    if (this.renderer !== null) {
      return;
    }

    const renderer: audio.AudioRenderer = await audio.createAudioRenderer({
      streamInfo: {
        samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_48000,
        channels: audio.AudioChannel.CHANNEL_1,
        sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
        encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
      },
      rendererInfo: {
        usage: audio.StreamUsage.STREAM_USAGE_MOVIE,
        rendererFlags: 0
      }
    });

    renderer.on(
      'writeData',
      (data: ArrayBuffer): audio.AudioDataCallbackResult => {
        return this.fillPlaybackBuffer(data);
      }
    );

    try {
      await renderer.start();
      this.renderer = renderer;
    } catch (error) {
      const reason: string = error instanceof Error ? error.message : String(error);

      try {
        await renderer.release();
      } catch (releaseError) {
        const releaseReason: string = releaseError instanceof Error ?
          releaseError.message : String(releaseError);
        XmaxLogger.error(
          `释放本地音频播放器失败\n└─ 原因：${releaseReason}`,
          'Audio'
        );
      }

      throw new Error(reason);
    }
  }

  /**
   * 将一帧 PCM 音频加入待播放缓冲区。
   *
   * @param frame 待播放的 PCM 音频帧。
   * @returns 无返回值。
   */
  write(frame: AudioFrame): void {
    if (this.renderer === null || !this.isPlaybackEnabled) {
      return;
    }

    this.pendingFrames.push(frame.data);
  }

  /**
   * 启用或暂停本地音频预览。
   *
   * 暂停后继续由上游处理音频帧，但本地播放器仅输出静音数据。
   *
   * @param enabled 是否播放本地预览音频。
   * @returns 无返回值。
   */
  setPlaybackEnabled(enabled: boolean): void {
    if (this.isPlaybackEnabled === enabled) {
      return;
    }

    this.isPlaybackEnabled = enabled;
    if (!enabled) {
      this.clearPendingFrames();
    }
  }

  /**
   * 清除平台播放器及本地队列中尚未播放的音频数据。
   *
   * @returns 缓冲区清理完成后的 Promise。
   */
  async flush(): Promise<void> {
    const renderer: audio.AudioRenderer | null = this.renderer;
    this.clearPendingFrames();

    if (renderer !== null) {
      await renderer.flush();
      this.clearPendingFrames();
    }
  }

  /**
   * 停止本地音频播放并释放平台资源。
   *
   * @returns 播放器停止完成后的 Promise。
   */
  async stop(): Promise<void> {
    const renderer: audio.AudioRenderer | null = this.renderer;
    this.renderer = null;
    this.isPlaybackEnabled = true;
    this.clearPendingFrames();

    if (renderer === null) {
      return;
    }

    try {
      await renderer.stop();
    } catch (error) {
      const reason: string = error instanceof Error ? error.message : String(error);
      XmaxLogger.error(
        `停止本地音频播放器失败\n└─ 原因：${reason}`,
        'Audio'
      );
    }

    try {
      await renderer.release();
    } catch (error) {
      const reason: string = error instanceof Error ? error.message : String(error);
      XmaxLogger.error(
        `释放本地音频播放器失败\n└─ 原因：${reason}`,
        'Audio'
      );
    }
  }

  /**
   * 使用待播放音频帧填充平台请求的播放缓冲区。
   *
   * @param data 平台提供的播放缓冲区。
   * @returns 平台音频数据回调处理结果。
   */
  private fillPlaybackBuffer(data: ArrayBuffer): audio.AudioDataCallbackResult {
    const output = new Uint8Array(data);
    if (!this.isPlaybackEnabled) {
      output.fill(0);
      return audio.AudioDataCallbackResult.VALID;
    }

    let outputOffset: number = 0;

    while (outputOffset < output.length && this.pendingFrames.length > 0) {
      const frame: Uint8Array = this.pendingFrames[0];
      const availableLength: number = frame.length - this.pendingFrameOffset;
      const copyLength: number = Math.min(
        availableLength,
        output.length - outputOffset
      );

      output.set(
        frame.subarray(
          this.pendingFrameOffset,
          this.pendingFrameOffset + copyLength
        ),
        outputOffset
      );
      outputOffset += copyLength;
      this.pendingFrameOffset += copyLength;

      if (this.pendingFrameOffset === frame.length) {
        this.pendingFrames.shift();
        this.pendingFrameOffset = 0;
      }
    }

    if (outputOffset < output.length) {
      output.fill(0, outputOffset);
    }

    return audio.AudioDataCallbackResult.VALID;
  }

  /**
   * 清空待播放音频帧及当前帧读取偏移量。
   *
   * @returns 无返回值。
   */
  private clearPendingFrames(): void {
    this.pendingFrames = [];
    this.pendingFrameOffset = 0;
  }
}
