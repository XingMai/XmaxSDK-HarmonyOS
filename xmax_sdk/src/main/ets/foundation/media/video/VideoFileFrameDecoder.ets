//
//  VideoFileFrameDecoder.ets
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
  NativeVideoFileDecoder
} from 'libxmax_video.so';
import { VideoPixelFormat } from './VideoPixelFormat';
import { VideoRotation } from './VideoRotation';

/** 系统视频解码器连续输出的单个文件视频帧。 */
export class VideoFileDecodedFrame {

  /** 解码像素数据与帧布局 */
  readonly data: ArrayBuffer;
  readonly width: number;
  readonly height: number;
  readonly stride: number;
  readonly timestampUs: number;
  readonly pixelFormat: VideoPixelFormat;

  /**
   * 创建原生解码视频帧。
   *
   * @param data 当前帧的有效媒体数据。
   * @param width 画面宽度，单位像素。
   * @param height 画面高度，单位像素。
   * @param stride 相邻图像行之间的字节跨度。
   * @param timestampUs 媒体帧时间戳，单位微秒。
   * @returns 新建的 VideoFileDecodedFrame 实例。
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

/** 文件视频连续解码事件。 */
export interface VideoFileFrameDecoderListener {
  /**
   * 接收按媒体时间轴输出的解码帧。
   *
   * @param frame 解码后的音频帧。
   * @returns 无返回值。
   */
  onFrame(frame: VideoFileDecodedFrame): void;

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

/**
 * 使用系统视频解码器按媒体时间戳连续输出已转正的 NV12 帧。
 *
 * 解码结果由媒体层转换为统一视频帧，并交由后续业务链路处理。
 */
export class VideoFileFrameDecoder {

  /** 解码初始化与原生资源 */
  readonly ready: Promise<void>;
  private nativeDecoder: NativeVideoFileDecoder | null = null;

  /** 释放状态与异步释放等待 */
  private isReleased: boolean = false;
  private releasePromise: Promise<void> | null = null;

  /** 输出激活与暂停状态 */
  private isActivated: boolean = false;
  private isPaused: boolean = false;
  private activationOffsetUs: number = 0;

  /**
   * 创建视频文件解码器。
   *
   * @param videoUri 需要解码的本地视频文件 URI。
   * @param rotation 视频画面需要应用的旋转方向。
   * @param outputWidth 解码输出宽度，单位像素。
   * @param outputHeight 解码输出高度，单位像素。
   * @param frameIntervalUs 视频帧输出间隔，单位微秒。
   * @param listener 接收媒体帧与解码状态的监听器。
   * @param playbackAnchorUs 媒体起点对应的单调播放时间，单位微秒。
   * @param mediaStartUs 媒体时间轴的起始时间，单位微秒。
   * @param cycleDurationUs 单轮媒体播放时长，单位微秒。
   * @returns 新建的 VideoFileFrameDecoder 实例。
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
    this.ready = this.initialize(videoUri, rotation, outputWidth, outputHeight,
      frameIntervalUs, listener, playbackAnchorUs, mediaStartUs, cycleDurationUs);
  }

  /**
   * 异步创建文件视频解码器，并应用待处理的激活或暂停状态。
   *
   * @param videoUri 需要解码的本地视频文件 URI。
   * @param rotation 视频画面需要应用的旋转方向。
   * @param outputWidth 解码输出宽度，单位像素。
   * @param outputHeight 解码输出高度，单位像素。
   * @param frameIntervalUs 视频帧输出间隔，单位微秒。
   * @param listener 接收媒体帧与解码状态的监听器。
   * @param playbackAnchorUs 媒体起点对应的单调播放时间，单位微秒。
   * @param mediaStartUs 媒体时间轴的起始时间，单位微秒。
   * @param cycleDurationUs 单轮媒体播放时长，单位微秒。
   * @returns 操作完成时兑现的 Promise。
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
   * 就绪后一次性放行；正在暂停时保留校准量，等待恢复。
   *
   * @param anchorOffsetUs 相对播放锚点的偏移量，单位微秒。
   * @returns 无返回值。
   */
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

  /**
   * 暂停视频文件的连续解码输出。
   *
   * @returns 无返回值。
   */
  pause(): void {
    this.isPaused = true;
    if (!this.isReleased && this.isActivated && this.nativeDecoder !== null) {
      this.nativeDecoder.pause();
    }
  }

  /**
   * 恢复视频解码，并按暂停时长平移播放锚点。
   *
   * @param pausedDurationUs 本次暂停持续时间，单位微秒。
   * @returns 无返回值。
   */
  resume(pausedDurationUs: number): void {
    this.isPaused = false;
    if (!this.isReleased && this.isActivated && this.nativeDecoder !== null) {
      this.nativeDecoder.resume(this.activationOffsetUs + pausedDurationUs);
      this.activationOffsetUs = 0;
    }
  }

  /**
   * 停止视频帧输出，并等待原生解码资源释放完成。
   *
   * @returns 操作完成时兑现的 Promise。
   */
  release(): Promise<void> {
    if (this.releasePromise === null) {
      this.isReleased = true;
      this.releasePromise = this.releaseWhenReady();
    }
    return this.releasePromise;
  }

  /**
   * 等待视频解码器创建结束后释放原生资源。
   *
   * @returns 操作完成时兑现的 Promise。
   */
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
