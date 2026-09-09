import { display } from '@kit.ArkUI';
import { camera } from '@kit.CameraKit';
import xmaxVideoNative, {
  NativeFrameReceiver
} from 'libxmax_video.so';
import {
  XmaxError,
  XmaxErrorCode,
  XmaxErrorListener,
  XmaxErrorSeverity
} from '../../foundation/errors/XmaxError';
import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import { BufferVideoFrame } from '../../foundation/media/video/BufferVideoFrame';
import { VideoFormat } from '../../foundation/media/video/VideoFormat';
import { VideoFrame } from '../../foundation/media/video/VideoFrame';
import { VideoFramePlane } from '../../foundation/media/video/VideoFramePlane';
import { VideoPixelFormat } from '../../foundation/media/video/VideoPixelFormat';
import { VideoRotation } from '../../foundation/media/video/VideoRotation';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import { CameraFrameStatistics } from './CameraFrameStatistics';

export type CameraFrameListener = (frame: VideoFrame) => void;

/** 管理相机原始视频帧输出。 */
export class CameraFrameOutput {
  // 平台资源
  readonly output: camera.PreviewOutput;
  private readonly receiver: NativeFrameReceiver;
  private readonly statistics: CameraFrameStatistics;
  private readonly position: camera.CameraPosition;
  private videoFormat: RealtimeVideoFormat | null = null;
  private captureFrameRate: number = 0;
  private rotation: VideoRotation = VideoRotation.ROTATION_0;
  private isListeningForDisplayChanges: boolean = false;
  private isReleased: boolean = false;
  private readonly displayChangeListener = (displayId: number): void => {
    this.handleDisplayChange(displayId);
  };

  private constructor(
    output: camera.PreviewOutput,
    receiver: NativeFrameReceiver,
    statistics: CameraFrameStatistics,
    position: camera.CameraPosition
  ) {
    this.output = output;
    this.receiver = receiver;
    this.statistics = statistics;
    this.position = position;
  }

  static create(
    manager: camera.CameraManager,
    profile: camera.Profile,
    position: camera.CameraPosition,
    listener: CameraFrameListener,
    errorListener: XmaxErrorListener = (_error: XmaxError): void => {}
  ): CameraFrameOutput {
    const statistics: CameraFrameStatistics = new CameraFrameStatistics();
    const receiver: NativeFrameReceiver = xmaxVideoNative.createFrameReceiver(
      profile.size.width,
      profile.size.height,
      (
        data: ArrayBuffer | undefined,
        width: number,
        height: number,
        timestampUs: number,
        error?: string,
        processingMilliseconds?: number,
        _droppedFrames?: number,
        _skippedFrames?: number,
        _conversionBackend?: string,
        threadCpuMilliseconds?: number,
        sampleTimeMilliseconds?: number
      ): void => {
        CameraFrameOutput.handleNativeFrame(
          statistics,
          listener,
          errorListener,
          data,
          width,
          height,
          timestampUs,
          error,
          processingMilliseconds,
          threadCpuMilliseconds,
          sampleTimeMilliseconds
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
        statistics,
        position
      );
    } catch (error) {
      receiver.release();

      throw error as Error;
    }
  }

  configure(
    videoFormat: RealtimeVideoFormat,
    captureFrameRate: number
  ): void {
    if (this.isReleased) {
      return;
    }
    if (!this.isListeningForDisplayChanges) {
      display.on('change', this.displayChangeListener);
      this.isListeningForDisplayChanges = true;
    }
    const rotation: VideoRotation = this.rotationForDisplay(
      display.getDefaultDisplaySync().rotation * 90
    );
    this.configureNative(videoFormat, captureFrameRate, rotation);
  }

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
    this.statistics.restart();
  }

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
      if (rotation !== this.rotation) {
        this.configureNative(videoFormat, this.captureFrameRate, rotation);
      }
    } catch (error) {
      this.logError('更新相机帧旋转角度', error);
    }
  }

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
        this.logError('移除相机屏幕变化监听', error);
      }
    }
    try {
      await this.output.release();
    } catch (error) {
      this.logError('释放相机视频帧输出', error);
    }

    try {
      this.receiver.release();
    } catch (error) {
      this.logError('释放 Native 相机视频帧接收器', error);
    }
  }

  private static handleNativeFrame(
    statistics: CameraFrameStatistics,
    listener: CameraFrameListener,
    errorListener: XmaxErrorListener,
    data: ArrayBuffer | undefined,
    width: number,
    height: number,
    timestampUs: number,
    error?: string,
    processingMilliseconds?: number,
    threadCpuMilliseconds?: number,
    sampleTimeMilliseconds?: number
  ): void {
    if (error !== undefined) {
      XmaxLogger.error(
        `接收 Native 相机视频帧失败\n└─ 原因：${error}`,
        'Camera'
      );
      try {
        errorListener(new XmaxError(
          XmaxErrorCode.MEDIA_ERROR,
          error,
          undefined,
          undefined,
          XmaxErrorSeverity.RECOVERABLE
        ));
      } catch (listenerError) {
        const reason: string = listenerError instanceof Error ?
          listenerError.message : String(listenerError);
        XmaxLogger.error(`相机错误监听器执行失败\n└─ 原因：${reason}`, 'Camera');
      }
      return;
    }
    if (data === undefined || width <= 0 || height <= 0) {
      return;
    }

    statistics.record(
      processingMilliseconds ?? 0,
      threadCpuMilliseconds,
      sampleTimeMilliseconds
    );

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
        `处理 Native 相机视频帧失败\n└─ 原因：${reason}`,
        'Camera'
      );
    }
  }

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

  private logError(
    action: string,
    error: Object
  ): void {
    const errorMessage: string = error instanceof Error ? error.message : String(error);
    const reason: string = errorMessage.length > 0 && errorMessage !== 'undefined' ?
      errorMessage : '未知错误';
    XmaxLogger.error(
      `${action}失败\n└─ 原因：${reason}`,
      'Camera'
    );
  }
}
