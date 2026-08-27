import { common } from '@kit.AbilityKit';
import {
  XmaxError,
  XmaxErrorCode
} from '../../foundation/errors/XmaxError';
import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import { CameraPosition } from '../../foundation/media/camera/CameraPosition';
import { PermissionManager } from '../../foundation/permissions/PermissionManager';
import { PermissionManaging } from '../../foundation/permissions/PermissionManaging';
import { RtcManaging } from '../../foundation/rtc/RtcManaging';
import { VideoContentMode } from '../../foundation/media/video/VideoContentMode';
import { CameraPreviewRatio } from '../../rendering/video/CameraPreviewRatio';
import {
  VideoRenderBinding,
  VideoRenderRegistry
} from '../../rendering/video/VideoRenderRegistry';
import { ImageSize } from '../../service/media/ImageSize';
import { MediaService } from '../../service/media/MediaService';
import { MediaServicing } from '../../service/media/MediaServicing';
import { RealtimeMediaStream } from '../../service/realtime/RealtimeMediaStream';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import {
  RealtimeVideoTrack,
  updateRealtimeVideoTrackFormat,
  updateRealtimeVideoTrackPosition
} from '../../service/realtime/RealtimeVideoTrack';
import { StreamControlling } from '../../stream/StreamControlling';
import { StreamId } from '../../stream/StreamId';

const CAMERA_REPLACEMENT_DELAY_MS: number = 150;

/** 协调相机权限、采集、编码和本地预览资源。 */
export class CameraController {

  // 基础层组件
  private readonly rtcManager: RtcManaging;
  private readonly permissionManager: PermissionManaging;

  // 服务层组件
  private readonly mediaService: MediaServicing;

  // 业务层组件
  private readonly streamController: StreamControlling;

  // 本地资源
  private activeTrack: RealtimeVideoTrack | null = null;

  /**
   * 创建相机媒体 Controller。
   *
   * @param context 申请相机权限所需的页面上下文。
   * @param rtcManager 相机采集和本地渲染使用的 RTC 基础能力。
   * @param streamController 提供视频编码配置能力的统一流组件。
   */
  constructor(
    context: common.UIAbilityContext,
    rtcManager: RtcManaging,
    streamController: StreamControlling
  ) {
    // 基础层组件
    this.rtcManager = rtcManager;
    this.permissionManager = new PermissionManager(context);

    // 服务层组件
    this.mediaService = new MediaService();

    // 业务层组件
    this.streamController = streamController;
  }

  /** @returns 当前活动的本地相机视频轨道；尚未创建时返回空值。 */
  get currentTrack(): RealtimeVideoTrack | null {
    return this.activeTrack;
  }

  /**
   * 创建并启动本地相机流。
   *
   * @param videoFormat 相机流使用的视频输出格式。
   * @param position 初始摄像头位置。
   * @returns 创建完成后的本地相机媒体流。
   */
  async createLocalCameraStream(
    videoFormat: RealtimeVideoFormat,
    position: CameraPosition
  ): Promise<RealtimeMediaStream> {
    if (this.activeTrack !== null) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Stop the current local camera stream before creating another one'
      );
    }

    return this.createStream(
      videoFormat,
      position
    );
  }

  /**
   * 保留本地视频轨道并重新启动指定摄像头的采集。
   *
   * @param videoFormat 相机流使用的新视频输出格式。
   * @param position 需要启用的摄像头位置。
   * @returns 复用当前视频轨道的本地媒体流。
   */
  async replaceLocalCameraStream(
    videoFormat: RealtimeVideoFormat,
    position: CameraPosition
  ): Promise<RealtimeMediaStream> {
    const track: RealtimeVideoTrack | null = this.activeTrack;
    if (track === null) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Create a local camera stream before replacing it'
      );
    }

    const resolvedFormat: RealtimeVideoFormat = this.resolveVideoFormat(
      videoFormat
    );

    this.rtcManager.stopVideoCapture();
    this.streamController.setVideoEncoderConfig(resolvedFormat);
    this.rtcManager.switchCamera(position);
    this.rtcManager.startVideoCapture(
      resolvedFormat.width,
      resolvedFormat.height,
      resolvedFormat.fps
    );

    // 等待新摄像头画面进入 RTC 采集与编码链路。
    await new Promise<void>((resolve: () => void): void => {
      setTimeout(resolve, CAMERA_REPLACEMENT_DELAY_MS);
    });

    updateRealtimeVideoTrackFormat(track, resolvedFormat);
    updateRealtimeVideoTrackPosition(track, position);

    return new RealtimeMediaStream(StreamId.LOCAL, track);
  }

  /**
   * 停止相机采集并释放本地预览绑定。
   *
   * @returns 停止操作完成后的 Promise。
   */
  async stopLocalCameraStream(): Promise<void> {
    const track: RealtimeVideoTrack | null = this.activeTrack;
    this.activeTrack = null;

    if (track !== null) {
      VideoRenderRegistry.unregister(track);
      this.rtcManager.unbindLocalVideo();
    }

    try {
      this.rtcManager.stopVideoCapture();
    } catch (error) {
      const reason: string = error instanceof Error ? error.message : String(error);
      XmaxLogger.error(
        `停止 RTC 相机采集失败\n└─ 原因：${reason}`,
        'Realtime'
      );
    }
  }

  /**
   * 在前置和后置摄像头之间切换。
   *
   * @returns 更新摄像头位置后的本地媒体流。
   */
  async switchCamera(): Promise<RealtimeMediaStream> {
    const currentTrack: RealtimeVideoTrack | null = this.activeTrack;
    const videoFormat: RealtimeVideoFormat | undefined = currentTrack?.videoFormat;
    const position: CameraPosition | undefined = currentTrack?.position;

    if (currentTrack === null || videoFormat === undefined || position === undefined) {
      throw new XmaxError(XmaxErrorCode.RTC_ERROR, 'Local camera preview is not started');
    }

    const nextPosition: CameraPosition = position === CameraPosition.FRONT ?
      CameraPosition.BACK : CameraPosition.FRONT;

    this.rtcManager.switchCamera(nextPosition);
    updateRealtimeVideoTrackPosition(currentTrack, nextPosition);

    return new RealtimeMediaStream(StreamId.LOCAL, currentTrack);
  }

  /**
   * 完成相机权限检查、采集启动和预览注册。
   *
   * @param videoFormat 相机流使用的视频输出格式。
   * @param position 初始摄像头位置。
   * @returns 完成底层资源装配后的本地相机媒体流。
   */
  private async createStream(
    videoFormat: RealtimeVideoFormat,
    position: CameraPosition
  ): Promise<RealtimeMediaStream> {
    const resolvedFormat: RealtimeVideoFormat = this.resolveVideoFormat(videoFormat);
    const track = new RealtimeVideoTrack(
      'video0',
      resolvedFormat,
      position
    );

    try {
      await this.permissionManager.ensureCameraPermission();
      this.streamController.setVideoEncoderConfig(resolvedFormat);
      this.rtcManager.switchCamera(position);
      this.rtcManager.startVideoCapture(
        resolvedFormat.width,
        resolvedFormat.height,
        resolvedFormat.fps
      );

      VideoRenderRegistry.register(track, new VideoRenderBinding(
        this.rtcManager.renderLibraryName(),
        (
          viewId: string,
          contentMode: VideoContentMode
        ): void => {
          this.rtcManager.bindLocalVideo(viewId, contentMode);
        },
        (_viewId: string): void => {
          this.rtcManager.unbindLocalVideo();
        },
        CameraPreviewRatio.FILL
      ));
      this.activeTrack = track;

      return new RealtimeMediaStream(StreamId.LOCAL, track);
    } catch (error) {
      VideoRenderRegistry.unregister(track);

      try {
        this.rtcManager.stopVideoCapture();
      } catch (stopError) {
        const reason: string = stopError instanceof Error ?
          stopError.message : String(stopError);
        XmaxLogger.error(
          `RTC 相机采集回滚失败\n└─ 原因：${reason}`,
          'Realtime'
        );
      }

      throw XmaxError.from(error);
    }
  }

  /**
   * 校验视频格式并将尺寸调整为模型支持的输入规格。
   *
   * @param videoFormat 接入方请求的视频格式。
   * @returns 尺寸完成适配后的视频格式。
   */
  private resolveVideoFormat(videoFormat: RealtimeVideoFormat): RealtimeVideoFormat {
    videoFormat.validate();

    const targetSize: ImageSize = this.mediaService.resolveModelInputSize(
      new ImageSize(videoFormat.width, videoFormat.height)
    );
    return new RealtimeVideoFormat(
      targetSize.width,
      targetSize.height,
      videoFormat.fps
    );
  }

}
