import {
  AudioFileFrameDecoder,
  AudioFileFrameDecoderListener
} from '../../foundation/media/audio/AudioFileFrameDecoder';
import { AudioFrame } from '../../foundation/media/audio/AudioFrame';
import { XmaxError, XmaxErrorCode } from '../../foundation/errors/XmaxError';
import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import { MediaTimeline } from '../MediaTimeline';
import { AudioSourceControlling } from './AudioSourceControlling';

export type AudioSourceFrameListener = (frame: AudioFrame) => void;
export type AudioSourceErrorListener = (message: string) => void;

/** 解码本地媒体文件中的音频轨，并按共享时间轴循环输出音频帧。 */
export class AudioSourceController implements AudioSourceControlling {

  // 音频帧监听器
  private readonly frameListener: AudioSourceFrameListener;
  private readonly errorListener: AudioSourceErrorListener;

  // 音频文件资源
  private decoder: AudioFileFrameDecoder | null = null;
  private filePath: string = '';

  // 播放进度
  private timeline: MediaTimeline | null = null;
  private loopIndex: number = 0;

  /**
   * 创建音频源 Controller。
   *
   * @param frameListener 音频帧输出监听器。
   * @param errorListener 音频源错误监听器。
   */
  constructor(
    frameListener: AudioSourceFrameListener,
    errorListener: AudioSourceErrorListener
  ) {
    this.frameListener = frameListener;
    this.errorListener = errorListener;
  }

  /**
   * 配置待解码的本地媒体文件。
   *
   * @param filePath 本地媒体文件路径。
   * @returns 无返回值。
   */
  configure(filePath: string): void {
    if (this.decoder !== null) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Stop the current audio source before configuring another file'
      );
    }

    this.filePath = filePath;
  }

  /**
   * 按共享时间轴开始输出音频帧。
   *
   * @param timeline 音视频共享播放时间轴。
   * @returns 无返回值。
   */
  start(timeline: MediaTimeline): void {
    if (this.filePath.length === 0) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Configure the local media file before starting the audio source'
      );
    }
    if (this.decoder !== null) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Local audio source is already active'
      );
    }

    this.timeline = timeline;
    this.loopIndex = 0;
    this.decoder = this.createDecoder();
  }

  /**
   * 释放当前解码器并按新时间轴重新输出音频帧。
   *
   * @param timeline 新的音视频共享播放时间轴。
   * @returns 无返回值。
   */
  restart(timeline: MediaTimeline): void {
    this.releaseDecoder();
    this.timeline = timeline;
    this.loopIndex = 0;
    this.decoder = this.createDecoder();
  }

  /**
   * 停止输出并清理音频文件状态。
   *
   * @returns 无返回值。
   */
  stop(): void {
    this.releaseDecoder();
    this.filePath = '';
    this.timeline = null;
    this.loopIndex = 0;
  }

  /**
   * 根据当前文件和时间轴创建音频帧解码器。
   *
   * @returns 已启动的音频帧解码器。
   */
  private createDecoder(): AudioFileFrameDecoder {
    const timeline: MediaTimeline | null = this.timeline;
    if (timeline === null) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Audio source timeline is unavailable'
      );
    }

    const loopIndex: number = this.loopIndex;
    return new AudioFileFrameDecoder(
      this.filePath,
      timeline.playbackAnchorForLoop(loopIndex),
      timeline.mediaStartUs,
      timeline.cycleDurationUs,
      new AudioSourceDecoderListener(
        (frame: AudioFrame): void => {
          this.frameListener(frame);
        },
        (): void => {
          this.handleEndOfStream(loopIndex);
        },
        (message: string): void => {
          this.errorListener(message);
        }
      )
    );
  }

  /**
   * 在当前循环结束后创建下一轮音频解码器。
   *
   * @param loopIndex 结束解码器所属的循环序号。
   * @returns 无返回值。
   */
  private handleEndOfStream(loopIndex: number): void {
    const endedDecoder: AudioFileFrameDecoder | null = this.decoder;
    if (endedDecoder === null || loopIndex !== this.loopIndex) {
      return;
    }

    setTimeout((): void => {
      if (this.decoder !== endedDecoder || loopIndex !== this.loopIndex) {
        return;
      }

      this.decoder = null;
      this.releaseDecoderInstance(endedDecoder);
      this.loopIndex++;

      try {
        this.decoder = this.createDecoder();
      } catch (error) {
        const reason: string = error instanceof Error ? error.message : String(error);
        this.errorListener(reason);
      }
    }, 0);
  }

  /**
   * 释放当前音频解码器。
   *
   * @returns 无返回值。
   */
  private releaseDecoder(): void {
    const decoder: AudioFileFrameDecoder | null = this.decoder;
    this.decoder = null;

    if (decoder !== null) {
      this.releaseDecoderInstance(decoder);
    }
  }

  /**
   * 安全释放指定音频解码器并记录释放错误。
   *
   * @param decoder 待释放的音频解码器。
   * @returns 无返回值。
   */
  private releaseDecoderInstance(decoder: AudioFileFrameDecoder): void {
    try {
      decoder.release();
    } catch (error) {
      const reason: string = error instanceof Error ? error.message : String(error);
      XmaxLogger.error(
        `释放本地音频解码器失败\n└─ 原因：${reason}`,
        'Audio'
      );
    }
  }
}

/** 将音频解码器事件转发给音频源 Controller。 */
class AudioSourceDecoderListener implements AudioFileFrameDecoderListener {

  private readonly frameHandler: (frame: AudioFrame) => void;
  private readonly endHandler: () => void;
  private readonly errorHandler: (message: string) => void;

  /**
   * 创建音频解码事件转发器。
   *
   * @param frameHandler 音频帧处理方法。
   * @param endHandler 音频流结束处理方法。
   * @param errorHandler 音频解码错误处理方法。
   */
  constructor(
    frameHandler: (frame: AudioFrame) => void,
    endHandler: () => void,
    errorHandler: (message: string) => void
  ) {
    this.frameHandler = frameHandler;
    this.endHandler = endHandler;
    this.errorHandler = errorHandler;
  }

  /**
   * 转发解码后的音频帧，并将处理异常交给错误处理器。
   *
   * @param frame 解码后的音频帧。
   * @returns 无返回值。
   */
  onFrame(frame: AudioFrame): void {
    try {
      this.frameHandler(frame);
    } catch (error) {
      const reason: string = error instanceof Error ? error.message : String(error);
      this.errorHandler(`处理本地音频帧失败：${reason}`);
    }
  }

  /**
   * 转发音频流结束事件。
   *
   * @returns 无返回值。
   */
  onEndOfStream(): void {
    this.endHandler();
  }

  /**
   * 转发音频解码错误。
   *
   * @param message 错误信息。
   * @returns 无返回值。
   */
  onError(message: string): void {
    this.errorHandler(message);
  }
}
