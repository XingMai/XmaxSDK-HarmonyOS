import { display } from '@kit.ArkUI';
import { camera } from '@kit.CameraKit';
import xmaxVideoNative, {
  NativeFrameReceiver,
  NativeCameraFrameTiming
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

  private constructor(
    output: camera.PreviewOutput,
    receiver: NativeFrameReceiver,
    statistics: CameraFrameStatistics
  ) {
    this.output = output;
    this.receiver = receiver;
    this.statistics = statistics;
  }

  static create(
    manager: camera.CameraManager,
    profile: camera.Profile,
    listener: CameraFrameListener,
    errorListener: XmaxErrorListener = (_error: XmaxError): void => {}
  ): CameraFrameOutput {
    const statistics: CameraFrameStatistics = new CameraFrameStatistics(profile.size.width, profile.size.height);
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
        droppedFrames?: number,
        skippedFrames?: number,
        conversionBackend?: string,
        threadCpuMilliseconds?: number,
        sampleTimeMilliseconds?: number,
        timing?: NativeCameraFrameTiming
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
          droppedFrames,
          skippedFrames,
          conversionBackend,
          threadCpuMilliseconds,
          sampleTimeMilliseconds,
          timing
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
        statistics
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
    const rotation: VideoRotation = this.currentRotation();
    this.statistics.configure(videoFormat, captureFrameRate, rotation);
    this.receiver.configure(
      videoFormat.width,
      videoFormat.height,
      rotation,
      videoFormat.fps,
      captureFrameRate
    );
  }

  async release(): Promise<void> {
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
    droppedFrames?: number,
    skippedFrames?: number,
    conversionBackend?: string,
    threadCpuMilliseconds?: number,
    sampleTimeMilliseconds?: number,
    timing?: NativeCameraFrameTiming
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
      droppedFrames ?? 0,
      skippedFrames ?? 0,
      conversionBackend ?? 'unknown',
      threadCpuMilliseconds,
      sampleTimeMilliseconds,
      timing
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

  private currentRotation(): VideoRotation {
    const displayRotation: number = display.getDefaultDisplaySync().rotation * 90;
    const rotation: camera.ImageRotation = this.output.getPreviewRotation(
      displayRotation
    );

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
