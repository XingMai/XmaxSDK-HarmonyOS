//
//  CameraFrameOutput.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { display } from '@kit.ArkUI';
import { camera } from '@kit.CameraKit';
import xmaxVideoNative, {
  NativeFrameReceiver
} from 'libxmax_video.so';
import {
  XmaxError,
  XmaxErrorCode,
  XmaxErrorListener
} from '../../foundation/errors/XmaxError';
import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import { BufferVideoFrame } from '../../foundation/media/video/BufferVideoFrame';
import { VideoFormat } from '../../foundation/media/video/VideoFormat';
import { VideoFrame } from '../../foundation/media/video/VideoFrame';
import { VideoFramePlane } from '../../foundation/media/video/VideoFramePlane';
import { VideoPixelFormat } from '../../foundation/media/video/VideoPixelFormat';
import { VideoRotation } from '../../foundation/media/video/VideoRotation';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';

/**
 * 接收经过尺寸和方向处理的摄像头视频帧。
 *
 * @param frame 需要处理或交付的媒体帧。
 * @returns 无返回值。
 */
export type CameraFrameListener = (frame: VideoFrame) => void;

/** 管理相机原始视频帧输出。 */
export class CameraFrameOutput {

  /** 平台输出与原生接收资源 */
  readonly output: camera.PreviewOutput;
  private readonly receiver: NativeFrameReceiver;

  /** 摄像头位置与输出格式 */
  private readonly position: camera.CameraPosition;
  private videoFormat: RealtimeVideoFormat | null = null;
  private captureFrameRate: number = 0;
  private rotation: VideoRotation = VideoRotation.ROTATION_0;

  /** 显示监听与资源释放状态 */
  private isListeningForDisplayChanges: boolean = false;
  private isReleased: boolean = false;
  /**
   * 接收系统显示变化并更新摄像头输出方向。
   *
   * @param displayId 发生变化的显示设备标识。
   * @returns 无返回值。
   */
  private readonly displayChangeListener = (displayId: number): void => {
    this.handleDisplayChange(displayId);
  };

  /**
   * 创建摄像头原始帧输出组件。
   *
   * @param output 平台摄像头输出资源。
   * @param receiver 负责接收和转换摄像头帧的原生资源。
   * @param position 使用的摄像头位置。
   * @returns 新建的 CameraFrameOutput 实例。
   */
  private constructor(
    output: camera.PreviewOutput,
    receiver: NativeFrameReceiver,
    position: camera.CameraPosition
  ) {
    this.output = output;
    this.receiver = receiver;
    this.position = position;
  }

  /**
   * 创建摄像头输出与原生帧接收器，将帧和错误交付给监听器。
   *
   * @param manager 用于创建摄像头输出的平台 CameraManager。
   * @param profile 摄像头采集规格。
   * @param position 使用的摄像头位置。
   * @param listener 接收媒体帧与解码状态的监听器。
   * @param errorListener 接收组件错误的监听器。
   * @returns 可连接到摄像头会话的帧输出组件。
   */
  static create(
    manager: camera.CameraManager,
    profile: camera.Profile,
    position: camera.CameraPosition,
    listener: CameraFrameListener,
    errorListener: XmaxErrorListener = (_error: XmaxError): void => {}
  ): CameraFrameOutput {
    const receiver: NativeFrameReceiver = xmaxVideoNative.createFrameReceiver(
      profile.size.width,
      profile.size.height,
      (
        data: ArrayBuffer | undefined,
        width: number,
        height: number,
        timestampUs: number,
        error?: string
      ): void => {
        CameraFrameOutput.handleNativeFrame(
          listener,
          errorListener,
          data,
          width,
          height,
          timestampUs,
          error
        );
      }
    );

    try {
      const output: camera.PreviewOutput = manager.createPreviewOutput(
        profile,
        receiver.getSurfaceId()
      );
      return new CameraFrameOutput(
        output,
        receiver,
        position
      );
    } catch (error) {
      receiver.release();

      throw error as Error;
    }
  }

  /**
   * 配置摄像头目标格式、采集帧率和显示方向监听。
   *
   * @param videoFormat 媒体输出或传输所需的视频规格。
   * @param captureFrameRate 采集帧率，单位 fps。
   * @param observeDisplayChange 是否跟随设备显示方向更新输出格式。
   * @returns 无返回值。
   */
  configure(
    videoFormat: RealtimeVideoFormat,
    captureFrameRate: number,
    observeDisplayChange: boolean = true
  ): void {
    if (this.isReleased) {
      return;
    }
    if (observeDisplayChange && !this.isListeningForDisplayChanges) {
      display.on('change', this.displayChangeListener);
      this.isListeningForDisplayChanges = true;
    }
    const currentDisplay: display.Display = display.getDefaultDisplaySync();
    const rotation: VideoRotation = this.rotationForDisplay(currentDisplay.rotation * 90);
    this.configureNative(this.formatForDisplay(videoFormat, currentDisplay), captureFrameRate, rotation);
  }

  /**
   * 读取已配置的摄像头输出格式。
   *
   * @returns 当前输出格式；尚未配置时返回 null。
   */
  get currentVideoFormat(): RealtimeVideoFormat | null {
    return this.videoFormat;
  }

  /**
   * 根据显示方向调整目标格式的宽高方向。
   *
   * @param format 需要使用的视频格式。
   * @param currentDisplay 提供当前设备显示方向的信息。
   * @returns 适合当前显示方向的视频格式。
   */
  private formatForDisplay(format: RealtimeVideoFormat, currentDisplay: display.Display): RealtimeVideoFormat {
    const shortSide: number = Math.min(format.width, format.height);
    const longSide: number = Math.max(format.width, format.height);
    const isLandscape: boolean = currentDisplay.orientation === display.Orientation.LANDSCAPE ||
      currentDisplay.orientation === display.Orientation.LANDSCAPE_INVERTED;
    return isLandscape ?
      format.resized(longSide, shortSide) :
      format.resized(shortSide, longSide);
  }

  /**
   * 将目标尺寸、旋转角度与采集帧率提交给原生帧接收器。
   *
   * @param videoFormat 媒体输出或传输所需的视频规格。
   * @param captureFrameRate 采集帧率，单位 fps。
   * @param rotation 视频画面需要应用的旋转方向。
   * @returns 无返回值。
   */
  private configureNative(
    videoFormat: RealtimeVideoFormat,
    captureFrameRate: number,
    rotation: VideoRotation
  ): void {
    this.receiver.configure(
      videoFormat.width,
      videoFormat.height,
      rotation,
      videoFormat.fps,
      captureFrameRate
    );
    this.videoFormat = videoFormat;
    this.captureFrameRate = captureFrameRate;
    this.rotation = rotation;
  }

  /**
   * 在显示设备方向变化时更新摄像头输出规格。
   *
   * @param displayId 发生变化的显示设备标识。
   * @returns 无返回值。
   */
  private handleDisplayChange(displayId: number): void {
    const videoFormat: RealtimeVideoFormat | null = this.videoFormat;
    if (this.isReleased || videoFormat === null) {
      return;
    }
    try {
      const currentDisplay: display.Display = display.getDefaultDisplaySync();
      if (currentDisplay.id !== displayId) {
        return;
      }
      const rotation: VideoRotation = this.rotationForDisplay(currentDisplay.rotation * 90);
      const outputFormat: RealtimeVideoFormat = this.formatForDisplay(videoFormat, currentDisplay);
      if (rotation !== this.rotation || outputFormat.width !== videoFormat.width ||
        outputFormat.height !== videoFormat.height) {
        this.configureNative(outputFormat, this.captureFrameRate, rotation);
      }
    } catch (error) {
      this.logError(XmaxLogger.localized("更新相机帧旋转角度", "Update Camera Frame Rotation"), error);
    }
  }

  /**
   * 停止显示方向监听与帧回调，释放摄像头输出和原生接收器。
   *
   * @returns 操作完成时兑现的 Promise。
   */
  async release(): Promise<void> {
    if (this.isReleased) {
      return;
    }
    this.isReleased = true;
    this.videoFormat = null;
    if (this.isListeningForDisplayChanges) {
      this.isListeningForDisplayChanges = false;
      try {
        display.off('change', this.displayChangeListener);
      } catch (error) {
        this.logError(XmaxLogger.localized("移除相机屏幕变化监听", "Remove Camera Display Change Listener"), error);
      }
    }
    try {
      await this.output.release();
    } catch (error) {
      this.logError(XmaxLogger.localized("释放相机视频帧输出", "Release Camera Frame Output"), error);
    }

    try {
      this.receiver.release();
    } catch (error) {
      this.logError(XmaxLogger.localized("释放 Native 相机视频帧接收器", "Release Native Camera Frame Receiver"), error);
    }
  }

  /**
   * 验证原生回调并交付 NV12 帧；处理失败时通知错误监听器。
   *
   * @param listener 接收媒体帧与解码状态的监听器。
   * @param errorListener 接收组件错误的监听器。
   * @param data 当前帧的有效媒体数据。
   * @param width 画面宽度，单位像素。
   * @param height 画面高度，单位像素。
   * @param timestampUs 媒体帧时间戳，单位微秒。
   * @param error 当前操作失败或终止的原因。
   * @returns 无返回值。
   */
  private static handleNativeFrame(
    listener: CameraFrameListener,
    errorListener: XmaxErrorListener,
    data: ArrayBuffer | undefined,
    width: number,
    height: number,
    timestampUs: number,
    error?: string
  ): void {
    if (error !== undefined) {
      XmaxLogger.error(
        `${XmaxLogger.localized("接收 Native 相机视频帧失败 (Native Camera Frame Receive Failed)\n└─ 原因：", "接收 Native 相机视频帧失败 (Native Camera Frame Receive Failed)\n└─ Reason: ")}${error}`,
        'Camera'
      );
      try {
        errorListener(new XmaxError(
          XmaxErrorCode.MEDIA_ERROR,
          error
        ));
      } catch (listenerError) {
        const reason: string = listenerError instanceof Error ?
          listenerError.message : String(listenerError);
        XmaxLogger.error(`${XmaxLogger.localized("相机错误监听器执行失败 (Camera Error Listener Failed)\n└─ 原因：", "相机错误监听器执行失败 (Camera Error Listener Failed)\n└─ Reason: ")}${reason}`, 'Camera');
      }
      return;
    }
    if (data === undefined || width <= 0 || height <= 0) {
      return;
    }

    const lumaLength: number = width * height;
    const frame: VideoFrame = new BufferVideoFrame(
      new VideoFormat(width, height, VideoPixelFormat.NV12),
      timestampUs,
      [
        new VideoFramePlane(data, width, 0, lumaLength),
        new VideoFramePlane(
          data,
          width,
          lumaLength,
          lumaLength / 2
        )
      ]
    );

    try {
      listener(frame);
    } catch (frameError) {
      const reason: string = frameError instanceof Error ?
        frameError.message : String(frameError);
      XmaxLogger.error(
        `${XmaxLogger.localized("处理 Native 相机视频帧失败 (Native Camera Frame Processing Failed)\n└─ 原因：", "处理 Native 相机视频帧失败 (Native Camera Frame Processing Failed)\n└─ Reason: ")}${reason}`,
        'Camera'
      );
    }
  }

  /**
   * 根据显示方向和摄像头位置计算帧旋转方向。
   *
   * @param displayRotation 系统显示方向枚举值。
   * @returns 用于原生视频转换的旋转方向。
   */
  private rotationForDisplay(displayRotation: number): VideoRotation {
    let rotation: number = this.output.getPreviewRotation(
      displayRotation
    );
    // 原始前置帧在横屏时需补偿 180°，使后续 RTC 水平镜像保持正确方向。
    if (this.position === camera.CameraPosition.CAMERA_POSITION_FRONT &&
      (displayRotation === 90 || displayRotation === 270)) {
      rotation = (rotation + 180) % 360;
    }

    switch (rotation) {
      case camera.ImageRotation.ROTATION_90:
        return VideoRotation.ROTATION_90;
      case camera.ImageRotation.ROTATION_180:
        return VideoRotation.ROTATION_180;
      case camera.ImageRotation.ROTATION_270:
        return VideoRotation.ROTATION_270;
      default:
        return VideoRotation.ROTATION_0;
    }
  }

  /**
   * 记录摄像头帧输出操作失败的原因。
   *
   * @param action 正在执行的资源操作名称或操作函数。
   * @param error 当前操作失败或终止的原因。
   * @returns 无返回值。
   */
  private logError(
    action: string,
    error: Object
  ): void {
    const errorMessage: string = error instanceof Error ? error.message : String(error);
    const reason: string = errorMessage.length > 0 && errorMessage !== 'undefined' ?
      errorMessage : XmaxLogger.localized("未知错误", "Unknown Error");
    XmaxLogger.error(
      `${action}${XmaxLogger.localized("失败\n└─ 原因：", " Failed\n└─ Reason: ")}${reason}`,
      'Camera'
    );
  }
}
