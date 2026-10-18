//
//  AudioSourceController.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import {
  AudioFileFrameDecoder,
  AudioFileFrameDecoderListener
} from '../../foundation/media/audio/AudioFileFrameDecoder';
import { AudioFrame } from '../../foundation/media/audio/AudioFrame';
import { XmaxError, XmaxErrorCode } from '../../foundation/errors/XmaxError';
import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import { MediaTimeline } from '../MediaTimeline';
import { AudioSourceControlling } from './AudioSourceControlling';

/**
 * 接收本地音频源解码后的 PCM 音频帧。
 *
 * @param frame 需要处理或交付的媒体帧。
 * @returns 无返回值。
 */
export type AudioSourceFrameListener = (frame: AudioFrame) => void;

/**
 * 接收本地音频源配置或解码失败的错误。
 *
 * @param message 日志内容、错误说明或收到的信令文本。
 * @returns 无返回值。
 */
export type AudioSourceErrorListener = (message: string) => void;

/** 解码本地媒体文件中的音频轨，并按共享时间轴循环输出音频帧。 */
export class AudioSourceController implements AudioSourceControlling {

  /** 帧与错误通知 */
  private readonly frameListener: AudioSourceFrameListener;
  private readonly errorListener: AudioSourceErrorListener;

  /** 文件解码与循环时间轴 */
  private decoder: AudioFileFrameDecoder | null = null;
  private filePath: string = '';

  /** 播放进度 */
  private timeline: MediaTimeline | null = null;
  private loopIndex: number = 0;

  /** 暂停、循环与文件结束状态 */
  private isPaused: boolean = false;
  private pendingEndOfStream: boolean = false;
  private loop: boolean = true;
  private hasEnded: boolean = false;

  /** 音频源版本与播放结束通知 */
  private sourceVersion: number = 0;
  /**
   * 通知本地媒体已完成当前播放。
   *
   * @returns 无返回值。
   */
  private readonly endedListener: () => void;

  /**
   * 创建音频源 Controller。
   *
   * @param frameListener 音频帧输出监听器。
   * @param errorListener 音频源错误监听器。
   * @param endedListener 当前媒体播放结束时执行的回调。
   * @returns 新建的 AudioSourceController 实例。
   */
  constructor(
    frameListener: AudioSourceFrameListener,
    errorListener: AudioSourceErrorListener,
    endedListener: () => void = (): void => {}
  ) {
    this.frameListener = frameListener;
    this.errorListener = errorListener;
    this.endedListener = endedListener;
  }

  /**
   * 配置待解码的本地媒体文件。
   *
   * @param filePath 本地媒体文件路径。
   * @param loop 是否在文件结束后循环播放。
   * @returns 无返回值。
   */
  configure(filePath: string, loop: boolean = true): void {
    if (this.decoder !== null) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Stop the current audio source before configuring another file'
      );
    }

    this.filePath = filePath;
    this.loop = loop;
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
    this.sourceVersion++;
    this.hasEnded = false;
    this.loopIndex = 0;
    this.isPaused = false;
    this.pendingEndOfStream = false;
    this.decoder = this.createDecoder();
  }

  /**
   * 暂停当前解码器，保留媒体位置与资源。
   *
   * @returns 无返回值。
   */
  pause(): void {
    if (this.hasEnded) {
      return;
    }
    if (this.isPaused) {
      return;
    }
    const decoder: AudioFileFrameDecoder | null = this.decoder;
    if (decoder === null) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Local audio source is not active'
      );
    }
    this.isPaused = true;
    decoder.pause();
  }

  /**
   * 使用统一的暂停时长恢复当前解码器。
   *
   * @param pausedDurationUs 本次暂停持续时间，单位微秒。
   * @returns 无返回值。
   */
  resume(pausedDurationUs: number): void {
    if (this.hasEnded) {
      return;
    }
    if (!this.isPaused) {
      return;
    }
    const decoder: AudioFileFrameDecoder | null = this.decoder;
    if (decoder === null) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Local audio source is not active'
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
   * 停止输出并清理音频文件状态。
   *
   * @returns 无返回值。
   */
  stop(): void {
    this.sourceVersion++;
    this.hasEnded = false;
    this.releaseDecoder();
    this.filePath = '';
    this.timeline = null;
    this.loopIndex = 0;
    this.isPaused = false;
    this.pendingEndOfStream = false;
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
    const version: number = this.sourceVersion;
    return new AudioFileFrameDecoder(
      this.filePath,
      timeline.playbackAnchorForLoop(loopIndex),
      timeline.mediaStartUs,
      timeline.cycleDurationUs,
      new AudioSourceDecoderListener(
        (frame: AudioFrame): void => {
          if (version === this.sourceVersion && !this.isPaused && !this.hasEnded) {
            this.frameListener(frame);
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
    if (endedDecoder === null || loopIndex !== this.loopIndex || this.hasEnded) {
      return;
    }
    if (this.isPaused) {
      this.pendingEndOfStream = true;
      return;
    }

    setTimeout((): void => {
      if (this.decoder !== endedDecoder || loopIndex !== this.loopIndex) {
        return;
      }
      if (this.isPaused) {
        this.pendingEndOfStream = true;
        return;
      }

      this.decoder = null;
      this.releaseDecoderInstance(endedDecoder);
      if (!this.loop) {
        this.hasEnded = true;
        this.endedListener();
        return;
      }
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
        `${XmaxLogger.localized("释放本地音频解码器失败 (Failed to Release Local Audio Decoder)\n└─ 原因：", "释放本地音频解码器失败 (Failed to Release Local Audio Decoder)\n└─ Reason: ")}${reason}`,
        'Audio'
      );
    }
  }
}

/** 将音频解码器事件转发给音频源 Controller。 */
class AudioSourceDecoderListener implements AudioFileFrameDecoderListener {

  /** 解码帧、结束与错误处理 */
  /**
   * 交付当前源的解码帧。
   *
   * @param frame 当前解码的 PCM 音频帧。
   * @returns 无返回值。
   */
  private readonly frameHandler: (frame: AudioFrame) => void;
  /**
   * 通知当前源已输出到文件结尾。
   *
   * @returns 无返回值。
   */
  private readonly endHandler: () => void;
  /**
   * 交付当前源的解码或输出错误。
   *
   * @param message 日志内容、错误说明或收到的信令文本。
   * @returns 无返回值。
   */
  private readonly errorHandler: (message: string) => void;

  /**
   * 创建音频解码事件转发器。
   *
   * @param frameHandler 音频帧处理方法。
   * @param endHandler 音频流结束处理方法。
   * @param errorHandler 音频解码错误处理方法。
   * @returns 新建的 AudioSourceDecoderListener 实例。
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
      this.errorHandler(`${XmaxLogger.localized("处理本地音频帧失败：", "Local Audio Frame Processing Failed: ")}${reason}`);
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
