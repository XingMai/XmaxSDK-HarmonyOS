import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import {
  XmaxError,
  XmaxErrorCode
} from '../foundation/errors/XmaxError';
import { XmaxLogger } from '../foundation/logging/XmaxLogger';
import { CameraPosition } from '../foundation/media/camera/CameraPosition';
import { RtcManaging } from '../foundation/rtc/RtcManaging';
import { PreviewRelease } from '../rendering/video/LocalVideoPreviewControlling';
import { RealtimeMediaStream } from '../service/realtime/RealtimeMediaStream';
import { RealtimePoint } from '../service/realtime/RealtimePoint';
import { RealtimeVideoFormat } from '../service/realtime/RealtimeVideoFormat';
import { RealtimeVideoTrack } from '../service/realtime/RealtimeVideoTrack';
import { TransportControlling } from '../transport/TransportControlling';
import { CameraController } from './camera/CameraController';
import { ImageController } from './image/ImageController';
import { InteractionController } from './interaction/InteractionController';
import { InteractionControlling } from './interaction/InteractionControlling';
import { InteractionFrame } from './interaction/InteractionFrame';
import { MediaControlling } from './MediaControlling';
import { VideoController } from './video/VideoController';

type LocalMediaController = CameraController |
  VideoController |
  ImageController;
type LocalMediaCreation = () => Promise<RealtimeMediaStream>;

/** 记录当前本地媒体来源及其进行中的创建、相机更新和停止任务。 */
class ActiveLocalMediaSource {

  readonly controller: LocalMediaController;
  operationPromise: Promise<RealtimeMediaStream> | null = null;
  stopPromise: Promise<void> | null = null;

  /**
   * 创建活动媒体来源记录。
   *
   * @param controller 实际管理当前媒体来源的子 Controller。
   */
  constructor(controller: LocalMediaController) {
    this.controller = controller;
  }
}

/** 统一协调相机、视频和图片三类本地媒体来源的所有权与生命周期。 */
export class MediaController implements MediaControlling {

  // 基础层组件
  private readonly rtcManager: RtcManaging;

  // 本地媒体组件
  private readonly cameraController: CameraController;
  private readonly imageController: ImageController;
  private readonly interactionController: InteractionControlling;
  private readonly videoController: VideoController;

  // 本地媒体资源
  private activeSource: ActiveLocalMediaSource | null = null;

  /**
   * 创建媒体层统一 Controller。
   *
   * @param context 相机和媒体权限所需的页面上下文。
   * @param rtcManager 本地媒体来源共享的 RTC 基础能力。
   * @param transportController 提供编码配置和音视频帧传输能力的统一组件。
   * @param errorListener 持续媒体输出错误监听器。
   */
  constructor(
    context: common.UIAbilityContext,
    rtcManager: RtcManaging,
    transportController: TransportControlling,
    errorListener: (error: XmaxError) => void
  ) {
    // 基础层组件
    this.rtcManager = rtcManager;

    // 本地媒体组件
    this.cameraController = new CameraController(
      context,
      rtcManager,
      transportController
    );
    this.imageController = new ImageController(
      rtcManager,
      transportController,
      errorListener
    );
    this.interactionController = new InteractionController((
      taskId: string,
      points: RealtimePoint[]
    ): void => {
      transportController.sendTracks(taskId, points);
    });
    this.videoController = new VideoController(
      context,
      rtcManager,
      transportController,
      errorListener
    );
  }

  /** @returns 当前活动的本地视频轨道；没有媒体来源时返回空值。 */
  get currentTrack(): RealtimeVideoTrack | null {
    return this.activeSource?.controller.currentTrack ?? null;
  }

  /** @returns 当前本地视频格式；没有活动轨道时返回空值。 */
  get currentVideoFormat(): RealtimeVideoFormat | undefined {
    return this.currentTrack?.videoFormat;
  }

  /** @returns 当前活动的视频文件来源是否包含音轨。 */
  get hasAudio(): boolean {
    return this.activeSource?.controller === this.videoController &&
      this.videoController.hasAudio;
  }

  /** @inheritdoc */
  start(taskId: string, videoFormat: RealtimeVideoFormat): void {
    this.interactionController.start(taskId, videoFormat);
  }

  /** @inheritdoc */
  stop(): void {
    this.interactionController.stop();
  }

  /** @inheritdoc */
  submit(frame: InteractionFrame): void {
    this.interactionController.submit(frame);
  }

  /**
   * 创建相机媒体来源并取得本地媒体所有权。
   *
   * @param videoFormat 相机流使用的视频输出格式。
   * @param position 初始摄像头位置。
   * @returns 创建完成后的本地相机媒体流。
   */
  createLocalCameraStream(
    videoFormat: RealtimeVideoFormat,
    position: CameraPosition
  ): Promise<RealtimeMediaStream> {
    return this.createSource(
      this.cameraController,
      (): Promise<RealtimeMediaStream> =>
        this.cameraController.createLocalCameraStream(videoFormat, position)
    );
  }

  /**
   * 更新当前相机来源的采集参数。
   *
   * @param videoFormat 相机流使用的视频输出格式。
   * @param position 初始摄像头位置。
   * @returns 更新完成后的本地相机媒体流。
   */
  replaceLocalCameraStream(
    videoFormat: RealtimeVideoFormat,
    position: CameraPosition
  ): Promise<RealtimeMediaStream> {
    return this.updateCameraSource(
      (): Promise<RealtimeMediaStream> =>
        this.cameraController.replaceLocalCameraStream(videoFormat, position)
    );
  }

  /** @returns 当前相机来源停止完成后的 Promise。 */
  stopLocalCameraStream(): Promise<void> {
    return this.stopSource(this.cameraController);
  }

  /** @returns 摄像头切换后的本地媒体流。 */
  switchCamera(): Promise<RealtimeMediaStream> {
    return this.cameraController.switchCamera();
  }

  /**
   * 创建视频文件媒体来源并取得本地媒体所有权。
   *
   * @param filePath 本地视频文件路径。
   * @param videoFormat 可选的视频输出格式。
   * @returns 创建完成后的本地视频媒体流。
   */
  createLocalVideoStream(
    filePath: string,
    videoFormat?: RealtimeVideoFormat
  ): Promise<RealtimeMediaStream> {
    return this.createSource(
      this.videoController,
      (): Promise<RealtimeMediaStream> =>
        this.videoController.createLocalVideoStream(filePath, videoFormat)
    );
  }

  /** @returns 当前视频文件来源停止完成后的 Promise。 */
  stopLocalVideoStream(): Promise<void> {
    return this.stopSource(this.videoController);
  }

  /**
   * 创建图片媒体来源并取得本地媒体所有权。
   *
   * @param source 本地文件路径、图片编码数据或平台 PixelMap。
   * @param videoFormat 可选的视频输出格式。
   * @returns 创建完成后的本地图片媒体流。
   */
  createLocalImageStream(
    source: string | ArrayBuffer | Uint8Array | image.PixelMap,
    videoFormat?: RealtimeVideoFormat
  ): Promise<RealtimeMediaStream> {
    return this.createSource(
      this.imageController,
      (): Promise<RealtimeMediaStream> =>
        this.imageController.createLocalImageStream(source, videoFormat)
    );
  }

  /** @returns 当前图片来源停止完成后的 Promise。 */
  stopLocalImageStream(): Promise<void> {
    return this.stopSource(this.imageController);
  }

  /**
   * 判断媒体流是否由当前活动来源创建并持有。
   *
   * @param stream 待检查的本地媒体流。
   * @returns 媒体流属于当前活动来源时返回 `true`。
   */
  owns(stream: RealtimeMediaStream): boolean {
    const track: RealtimeVideoTrack | undefined = stream.videoTrack;
    return track !== undefined && this.currentTrack === track;
  }

  /** @returns 解除视频预览冻结的回调；非视频来源返回空操作。 */
  freezePreview(): PreviewRelease {
    if (this.activeSource?.controller !== this.videoController) {
      return (): void => {};
    }

    return this.videoController.freezePreview();
  }

  /** @returns 视频文件时间线重启完成后的 Promise。 */
  async restartForGeneration(): Promise<void> {
    if (this.activeSource?.controller === this.videoController) {
      await this.videoController.restartForGeneration();
    }
  }

  /**
   * 在没有活动来源时创建新的本地媒体来源。
   *
   * @param controller 管理目标媒体类型的子 Controller。
   * @param create 实际创建本地媒体流的操作。
   * @returns 创建完成后的本地媒体流。
   */
  private async createSource(
    controller: LocalMediaController,
    create: LocalMediaCreation
  ): Promise<RealtimeMediaStream> {
    if (this.activeSource !== null) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Stop the current local media stream before creating another one'
      );
    }

    const source = new ActiveLocalMediaSource(controller);
    this.activeSource = source;

    const creationPromise: Promise<RealtimeMediaStream> = this.performCreate(
      source,
      create
    );
    source.operationPromise = creationPromise;

    try {
      return await creationPromise;
    } finally {
      if (source.operationPromise === creationPromise) {
        source.operationPromise = null;
      }
    }
  }

  /**
   * 在当前相机来源空闲时启动采集参数更新任务。
   *
   * @param update 实际更新相机来源的操作。
   * @returns 更新完成后的本地媒体流。
   */
  private async updateCameraSource(
    update: LocalMediaCreation
  ): Promise<RealtimeMediaStream> {
    const source: ActiveLocalMediaSource | null = this.activeSource;
    if (source === null || source.controller !== this.cameraController) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Create a local camera stream before updating it'
      );
    }
    if (source.operationPromise !== null || source.stopPromise !== null) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Another local media operation is already in progress'
      );
    }

    const updatePromise: Promise<RealtimeMediaStream> = update();
    source.operationPromise = updatePromise;

    try {
      return await updatePromise;
    } finally {
      if (source.operationPromise === updatePromise) {
        source.operationPromise = null;
      }
    }
  }

  /**
   * 初始化 RTC 后创建首个本地媒体来源。
   *
   * @param source 当前活动来源记录。
   * @param create 实际创建本地媒体流的操作。
   * @returns 创建完成后的本地媒体流。
   */
  private async performCreate(
    source: ActiveLocalMediaSource,
    create: LocalMediaCreation
  ): Promise<RealtimeMediaStream> {
    try {
      await this.rtcManager.initialize();
      this.ensureCreationActive(source);

      const stream: RealtimeMediaStream = await create();
      this.ensureCreationActive(source);

      return stream;
    } catch (error) {
      if (source.stopPromise === null) {
        await this.destroyRtcSafely('本地媒体创建回滚失败');

        if (this.activeSource === source) {
          this.activeSource = null;
        }
      }

      throw XmaxError.from(error);
    }
  }

  /**
   * 获取或创建指定媒体来源的停止任务。
   *
   * @param controller 需要停止的媒体子 Controller。
   * @returns 媒体来源停止完成后的 Promise。
   */
  private stopSource(controller: LocalMediaController): Promise<void> {
    const source: ActiveLocalMediaSource | null = this.activeSource;
    if (source === null || source.controller !== controller) {
      return Promise.resolve();
    }
    if (source.stopPromise !== null) {
      return source.stopPromise;
    }

    const stopPromise: Promise<void> = this.performStop(source);
    source.stopPromise = stopPromise;

    return stopPromise;
  }

  /**
   * 等待进行中的媒体操作结束并释放来源和 RTC 资源。
   *
   * @param source 需要停止的活动来源记录。
   * @returns 全部资源释放完成后的 Promise。
   */
  private async performStop(source: ActiveLocalMediaSource): Promise<void> {
    const operationPromise: Promise<RealtimeMediaStream> | null =
      source.operationPromise;
    if (operationPromise !== null) {
      try {
        await operationPromise;
      } catch (error) {
        if (!this.isCancelled(error)) {
          const reason: string = error instanceof Error ?
            error.message : String(error);
          XmaxLogger.error(
            `等待本地媒体创建结束失败\n└─ 原因：${reason}`,
            'Realtime'
          );
        }
      }
    }

    try {
      await this.stopController(source.controller);
    } finally {
      await this.destroyRtcSafely('释放本地媒体 RTC 资源失败');

      if (this.activeSource === source) {
        this.activeSource = null;
      }
    }
  }

  /**
   * 将停止请求分发给当前媒体类型对应的子 Controller。
   *
   * @param controller 需要停止的媒体子 Controller。
   * @returns 子 Controller 停止完成后的 Promise。
   */
  private stopController(controller: LocalMediaController): Promise<void> {
    if (controller === this.cameraController) {
      return this.cameraController.stopLocalCameraStream();
    }
    if (controller === this.videoController) {
      return this.videoController.stopLocalVideoStream();
    }

    return this.imageController.stopLocalImageStream();
  }

  /**
   * 确保创建或替换任务仍然持有本地媒体所有权。
   *
   * @param source 发起操作时记录的活动来源。
   * @returns 无返回值。
   */
  private ensureCreationActive(source: ActiveLocalMediaSource): void {
    if (this.activeSource === source && source.stopPromise === null) {
      return;
    }

    throw new XmaxError(
      XmaxErrorCode.CANCELLED,
      'Local media stream creation was cancelled'
    );
  }

  /**
   * 释放 RTC 资源并记录释放失败，但不覆盖原始业务错误。
   *
   * @param message 释放失败时使用的日志说明。
   * @returns 资源释放尝试完成后的 Promise。
   */
  private async destroyRtcSafely(message: string): Promise<void> {
    try {
      await this.rtcManager.destroy();
    } catch (error) {
      const reason: string = error instanceof Error ?
        error.message : String(error);
      XmaxLogger.error(
        `${message}\n└─ 原因：${reason}`,
        'Realtime'
      );
    }
  }

  /**
   * 判断错误是否表示生命周期操作被主动取消。
   *
   * @param error 待检查的错误对象。
   * @returns 错误码为 `CANCELLED` 时返回 `true`。
   */
  private isCancelled(error: Object): boolean {
    return error instanceof XmaxError &&
      error.code === XmaxErrorCode.CANCELLED;
  }

}
