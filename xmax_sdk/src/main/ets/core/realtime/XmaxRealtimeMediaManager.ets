import { common } from '@kit.AbilityKit';
import {
  XmaxError,
  XmaxErrorCode
} from '../../foundation/errors/XmaxError';
import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import { CameraPosition } from '../../foundation/media/camera/CameraPosition';
import { RtcProviding } from '../../foundation/rtc/RtcProviding';
import { PreviewRelease } from '../../rendering/video/LocalVideoPreviewControlling';
import { RealtimeMediaStream } from '../../service/realtime/RealtimeMediaStream';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import { RealtimeVideoTrack } from '../../service/realtime/RealtimeVideoTrack';
import { StreamControlling } from '../../transport/stream/StreamControlling';
import { XmaxRealtimeCameraManager } from './XmaxRealtimeCameraManager';
import { XmaxRealtimeImageManager } from './XmaxRealtimeImageManager';
import { XmaxRealtimeVideoManager } from './XmaxRealtimeVideoManager';

type LocalMediaManager = XmaxRealtimeCameraManager |
  XmaxRealtimeVideoManager |
  XmaxRealtimeImageManager;
type LocalMediaCreation = () => Promise<RealtimeMediaStream>;

/** 记录当前本地媒体来源及其进行中的创建、替换和停止任务。 */
class ActiveLocalMediaSource {

  manager: LocalMediaManager;
  operationPromise: Promise<RealtimeMediaStream> | null = null;
  stopPromise: Promise<void> | null = null;

  /**
   * 创建活动媒体来源记录。
   *
   * @param manager 实际管理当前媒体来源的子 Manager。
   */
  constructor(manager: LocalMediaManager) {
    this.manager = manager;
  }
}

/** 统一协调相机、视频和图片三类本地媒体来源的所有权与生命周期。 */
export class XmaxRealtimeMediaManager {

  // 基础层组件
  private readonly rtcProvider: RtcProviding;

  // 本地媒体组件
  private readonly cameraManager: XmaxRealtimeCameraManager;
  private readonly videoManager: XmaxRealtimeVideoManager;
  private readonly imageManager: XmaxRealtimeImageManager;

  // 本地媒体资源
  private activeSource: ActiveLocalMediaSource | null = null;

  /**
   * 创建本地媒体协调 Manager。
   *
   * @param context 相机和媒体权限所需的页面上下文。
   * @param rtcProvider 本地媒体来源共享的 RTC 基础能力。
   * @param streamController 接收外部视频和音频帧的传输组件。
   * @param errorListener 持续媒体输出错误监听器。
   */
  constructor(
    context: common.UIAbilityContext,
    rtcProvider: RtcProviding,
    streamController: StreamControlling,
    errorListener: (error: XmaxError) => void
  ) {
    // 基础层组件
    this.rtcProvider = rtcProvider;

    // 本地媒体组件
    this.cameraManager = new XmaxRealtimeCameraManager(
      context,
      rtcProvider
    );
    this.videoManager = new XmaxRealtimeVideoManager(
      context,
      rtcProvider,
      streamController,
      errorListener
    );
    this.imageManager = new XmaxRealtimeImageManager(
      rtcProvider,
      streamController,
      errorListener
    );
  }

  /** @returns 当前活动的本地视频轨道；没有媒体来源时返回空值。 */
  get currentTrack(): RealtimeVideoTrack | null {
    return this.activeSource?.manager.currentTrack ?? null;
  }

  /** @returns 当前本地视频格式；没有活动轨道时返回空值。 */
  get currentVideoFormat(): RealtimeVideoFormat | undefined {
    return this.currentTrack?.videoFormat;
  }

  /** @returns 当前活动的视频文件来源是否包含音轨。 */
  get hasAudio(): boolean {
    return this.activeSource?.manager === this.videoManager &&
      this.videoManager.hasAudio;
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
      this.cameraManager,
      (): Promise<RealtimeMediaStream> =>
        this.cameraManager.createLocalCameraStream(videoFormat, position)
    );
  }

  /**
   * 将当前本地媒体来源替换为相机流。
   *
   * @param videoFormat 相机流使用的视频输出格式。
   * @param position 初始摄像头位置。
   * @returns 替换完成后的本地相机媒体流。
   */
  replaceLocalCameraStream(
    videoFormat: RealtimeVideoFormat,
    position: CameraPosition
  ): Promise<RealtimeMediaStream> {
    return this.replaceSource(
      this.cameraManager,
      (): Promise<RealtimeMediaStream> =>
        this.cameraManager.createLocalCameraStream(videoFormat, position),
      (): Promise<RealtimeMediaStream> =>
        this.cameraManager.replaceLocalCameraStream(videoFormat, position)
    );
  }

  /** @returns 当前相机来源停止完成后的 Promise。 */
  stopLocalCameraStream(): Promise<void> {
    return this.stopSource(this.cameraManager);
  }

  /** @returns 摄像头切换后的本地媒体流。 */
  switchCamera(): Promise<RealtimeMediaStream> {
    return this.cameraManager.switchCamera();
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
      this.videoManager,
      (): Promise<RealtimeMediaStream> =>
        this.videoManager.createLocalVideoStream(filePath, videoFormat)
    );
  }

  /**
   * 将当前本地媒体来源替换为视频文件流。
   *
   * @param filePath 本地视频文件路径。
   * @param videoFormat 可选的视频输出格式。
   * @returns 替换完成后的本地视频媒体流。
   */
  replaceLocalVideoStream(
    filePath: string,
    videoFormat?: RealtimeVideoFormat
  ): Promise<RealtimeMediaStream> {
    return this.replaceSource(
      this.videoManager,
      (): Promise<RealtimeMediaStream> =>
        this.videoManager.createLocalVideoStream(filePath, videoFormat)
    );
  }

  /** @returns 当前视频文件来源停止完成后的 Promise。 */
  stopLocalVideoStream(): Promise<void> {
    return this.stopSource(this.videoManager);
  }

  /**
   * 创建图片文件媒体来源并取得本地媒体所有权。
   *
   * @param filePath 本地图片文件路径。
   * @param videoFormat 可选的视频输出格式。
   * @returns 创建完成后的本地图片媒体流。
   */
  createLocalImageStream(
    filePath: string,
    videoFormat?: RealtimeVideoFormat
  ): Promise<RealtimeMediaStream> {
    return this.createSource(
      this.imageManager,
      (): Promise<RealtimeMediaStream> =>
        this.imageManager.createLocalImageStream(filePath, videoFormat)
    );
  }

  /**
   * 将当前本地媒体来源替换为图片文件流。
   *
   * @param filePath 本地图片文件路径。
   * @param videoFormat 可选的视频输出格式。
   * @returns 替换完成后的本地图片媒体流。
   */
  replaceLocalImageStream(
    filePath: string,
    videoFormat?: RealtimeVideoFormat
  ): Promise<RealtimeMediaStream> {
    return this.replaceSource(
      this.imageManager,
      (): Promise<RealtimeMediaStream> =>
        this.imageManager.createLocalImageStream(filePath, videoFormat)
    );
  }

  /** @returns 当前图片来源停止完成后的 Promise。 */
  stopLocalImageStream(): Promise<void> {
    return this.stopSource(this.imageManager);
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
    if (this.activeSource?.manager !== this.videoManager) {
      return (): void => {};
    }

    return this.videoManager.freezePreview();
  }

  /** @returns 视频文件时间线重启完成后的 Promise。 */
  async restartForGeneration(): Promise<void> {
    if (this.activeSource?.manager === this.videoManager) {
      await this.videoManager.restartForGeneration();
    }
  }

  /**
   * 在没有活动来源时创建新的本地媒体来源。
   *
   * @param manager 管理目标媒体类型的子 Manager。
   * @param create 实际创建本地媒体流的操作。
   * @returns 创建完成后的本地媒体流。
   */
  private async createSource(
    manager: LocalMediaManager,
    create: LocalMediaCreation
  ): Promise<RealtimeMediaStream> {
    if (this.activeSource !== null) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Stop the current local media stream before creating another one'
      );
    }

    const source = new ActiveLocalMediaSource(manager);
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
   * 在当前来源空闲时启动媒体替换任务。
   *
   * @param manager 管理目标媒体类型的子 Manager。
   * @param create 实际创建新本地媒体流的操作。
   * @param replaceCurrent 同类型媒体来源原地替换操作。
   * @returns 替换完成后的本地媒体流。
   */
  private async replaceSource(
    manager: LocalMediaManager,
    create: LocalMediaCreation,
    replaceCurrent?: LocalMediaCreation
  ): Promise<RealtimeMediaStream> {
    const source: ActiveLocalMediaSource | null = this.activeSource;
    if (source === null) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Create a local media stream before replacing it'
      );
    }
    if (source.operationPromise !== null || source.stopPromise !== null) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Another local media operation is already in progress'
      );
    }

    const replacementPromise: Promise<RealtimeMediaStream> =
      source.manager === manager && replaceCurrent !== undefined ?
        replaceCurrent() : this.performReplace(source, manager, create);
    source.operationPromise = replacementPromise;

    try {
      return await replacementPromise;
    } finally {
      if (source.operationPromise === replacementPromise) {
        source.operationPromise = null;
      }
    }
  }

  /**
   * 停止旧来源并创建新的本地媒体来源。
   *
   * @param source 当前活动来源记录。
   * @param manager 管理目标媒体类型的子 Manager。
   * @param create 实际创建新本地媒体流的操作。
   * @returns 替换完成后的本地媒体流。
   */
  private async performReplace(
    source: ActiveLocalMediaSource,
    manager: LocalMediaManager,
    create: LocalMediaCreation
  ): Promise<RealtimeMediaStream> {
    try {
      await this.stopManager(source.manager);
      this.ensureCreationActive(source);

      source.manager = manager;
      const stream: RealtimeMediaStream = await create();
      this.ensureCreationActive(source);

      return stream;
    } catch (error) {
      throw XmaxError.from(error);
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
      await this.rtcProvider.initialize();
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
   * @param manager 需要停止的媒体子 Manager。
   * @returns 媒体来源停止完成后的 Promise。
   */
  private stopSource(manager: LocalMediaManager): Promise<void> {
    const source: ActiveLocalMediaSource | null = this.activeSource;
    if (source === null || source.manager !== manager) {
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
      await this.stopManager(source.manager);
    } finally {
      await this.destroyRtcSafely('释放本地媒体 RTC 资源失败');

      if (this.activeSource === source) {
        this.activeSource = null;
      }
    }
  }

  /**
   * 将停止请求分发给当前媒体类型对应的子 Manager。
   *
   * @param manager 需要停止的媒体子 Manager。
   * @returns 子 Manager 停止完成后的 Promise。
   */
  private stopManager(manager: LocalMediaManager): Promise<void> {
    if (manager === this.cameraManager) {
      return this.cameraManager.stopLocalCameraStream();
    }
    if (manager === this.videoManager) {
      return this.videoManager.stopLocalVideoStream();
    }

    return this.imageManager.stopLocalImageStream();
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
      await this.rtcProvider.destroy();
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
