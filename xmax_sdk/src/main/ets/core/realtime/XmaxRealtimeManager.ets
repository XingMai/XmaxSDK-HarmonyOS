import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import {
  XmaxError,
  XmaxErrorCode
} from '../../foundation/errors/XmaxError';
import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import { CameraPosition } from '../../foundation/media/camera/CameraPosition';
import { RtcManager } from '../../foundation/rtc/RtcManager';
import { RtcManaging } from '../../foundation/rtc/RtcManaging';
import { MediaController } from '../../media/MediaController';
import { MediaControlling } from '../../media/MediaControlling';
import { RenderController } from '../../rendering/RenderController';
import { RenderControlling } from '../../rendering/RenderControlling';
import { ApiServicing } from '../../service/network/ApiServicing';
import { RealtimeCameraPreviewReadyListener } from '../../service/realtime/RealtimeCameraPreview';
import { RealtimeContext } from '../../service/realtime/RealtimeContext';
import { RealtimeErrorListener } from '../../service/realtime/RealtimeError';
import { RealtimeMediaStream } from '../../service/realtime/RealtimeMediaStream';
import { RealtimeNetworkQualityListener } from '../../service/realtime/RealtimeNetworkQuality';
import { RealtimePerformanceAlarmListener } from '../../service/realtime/RealtimePerformanceAlarm';
import {
  RealtimeConnectionState,
  RealtimeState,
  RealtimeStateListener
} from '../../service/realtime/RealtimeState';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import { RealtimeVideoTrack } from '../../service/realtime/RealtimeVideoTrack';
import { StreamController } from '../../stream/StreamController';
import { StreamControlling } from '../../stream/StreamControlling';
import { RealtimeConfiguration } from './RealtimeConfiguration';
import { XmaxRealtimeConnectionManager } from './XmaxRealtimeConnectionManager';
import { XmaxRealtimeErrorManager } from './XmaxRealtimeErrorManager';
import { XmaxRealtimeGenerationManager } from './XmaxRealtimeGenerationManager';
import { XmaxRealtimeManaging } from './XmaxRealtimeManaging';

/** 实时生成业务公共入口，统一编排本地媒体、连接、生成和状态通知。 */
export class XmaxRealtimeManager implements XmaxRealtimeManaging {

  // 公共配置
  readonly options: RealtimeConfiguration;

  // 基础层组件
  private readonly rtcManager: RtcManaging;

  // 错误管理组件
  private readonly errorManager: XmaxRealtimeErrorManager;

  // 渲染层组件
  private readonly renderController: RenderControlling;

  // 业务层组件
  private readonly streamController: StreamControlling;
  private readonly mediaController: MediaControlling;

  // 实时管理组件
  private readonly connectionManager: XmaxRealtimeConnectionManager;
  private readonly generationManager: XmaxRealtimeGenerationManager;

  // 运行状态
  private terminationPromise: Promise<void> | null = null;
  private terminationFinalState: RealtimeConnectionState | null = null;
  private operationVersion: number = 0;
  private state: RealtimeState = new RealtimeState(RealtimeConnectionState.IDLE);
  private stateListener: RealtimeStateListener | null = null;

  /**
   * 创建实时生成业务 Manager 并完成内部依赖装配。
   *
   * @param context 访问 RTC、权限和渲染能力所需的页面上下文。
   * @param options 实时生成模型等业务配置。
   * @param apiService 创建和关闭实时会话使用的网络服务。
   */
  constructor(
    context: common.UIAbilityContext,
    options: RealtimeConfiguration,
    apiService: ApiServicing
  ) {
    // 公共配置
    this.options = options;

    // 基础层组件
    this.rtcManager = new RtcManager(context);

    // 错误管理组件
    this.errorManager = new XmaxRealtimeErrorManager();

    // 渲染层组件
    this.renderController = new RenderController(this.rtcManager);

    // 业务层组件
    this.streamController = new StreamController(
      this.rtcManager,
      (stream): void => {
        this.renderController.setRemoteStream(stream);
      }
    );
    this.mediaController = new MediaController(
      context,
      this.rtcManager,
      this.streamController,
      (error: XmaxError): void => {
        this.errorManager.handle(error);
      }
    );

    // 实时管理组件
    this.connectionManager = new XmaxRealtimeConnectionManager(
      apiService,
      this.mediaController,
      this.renderController,
      this.streamController
    );
    this.generationManager = new XmaxRealtimeGenerationManager(
      this.mediaController,
      this.streamController
    );
  }

  /** @returns 当前实时连接与生成状态。 */
  get currentState(): RealtimeState {
    return this.state;
  }

  /**
   * 设置实时连接状态监听器。
   *
   * @param listener 状态监听器；传入空值时清除监听器。
   * @returns 无返回值。
   */
  setStateListener(listener: RealtimeStateListener | null): void {
    this.stateListener = listener;
    this.notifyStateListener(this.state);
  }

  /**
   * 设置实时运行错误监听器。
   *
   * @param listener 错误监听器；传入空值时清除监听器。
   * @returns 无返回值。
   */
  setErrorListener(listener: RealtimeErrorListener | null): void {
    this.errorManager.setListener(listener);
  }

  /**
   * 设置实时网络质量监听器。
   *
   * @param listener 网络质量监听器；传入空值时清除监听器。
   * @returns 无返回值。
   */
  setNetworkQualityListener(listener: RealtimeNetworkQualityListener | null): void {
    this.streamController.setNetworkQualityListener(listener);
  }

  /**
   * 设置实时性能告警监听器。
   *
   * @param listener 性能告警监听器；传入空值时清除监听器。
   * @returns 无返回值。
   */
  setPerformanceAlarmListener(listener: RealtimePerformanceAlarmListener | null): void {
    this.streamController.setPerformanceAlarmListener(listener);
  }

  /**
   * 设置本地摄像头预览就绪监听器。
   *
   * @param listener 预览就绪监听器；传入空值时清除监听器。
   * @returns 无返回值。
   */
  setCameraPreviewReadyListener(
    listener: RealtimeCameraPreviewReadyListener | null
  ): void {
    this.mediaController.setCameraPreviewReadyListener(listener);
  }

  /**
   * 创建并启动本地相机流。
   *
   * @param videoFormat 相机流使用的视频输出格式。
   * @param position 初始摄像头位置；默认使用前置摄像头。
   * @returns 当前 Manager 持有的本地相机媒体流。
   */
  async createLocalCameraStream(
    videoFormat: RealtimeVideoFormat,
    position: CameraPosition = CameraPosition.FRONT
  ): Promise<RealtimeMediaStream> {
    if (this.connectionManager.currentSessionId.length > 0 || this.isConnecting() ||
      this.state.connectionState === RealtimeConnectionState.DISCONNECTING) {
      throw this.reportError(new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Local camera stream is unavailable during a realtime connection'
      ));
    }

    return this.observeError(this.mediaController.createLocalCameraStream(
      videoFormat,
      position
    ));
  }

  /**
   * 更新当前相机流的采集格式与摄像头位置。
   *
   * @param videoFormat 相机流使用的视频输出格式。
   * @param position 初始摄像头位置；默认使用前置摄像头。
   * @returns 更新完成后的本地相机媒体流。
   */
  async replaceLocalCameraStream(
    videoFormat: RealtimeVideoFormat,
    position: CameraPosition = CameraPosition.FRONT
  ): Promise<RealtimeMediaStream> {
    return this.updateLocalCameraStream(
      (): Promise<RealtimeMediaStream> =>
        this.mediaController.replaceLocalCameraStream(videoFormat, position)
    );
  }

  /**
   * 停止本地相机流并释放对应预览资源。
   *
   * @returns 停止操作完成后的 Promise。
   */
  async stopLocalCameraStream(): Promise<void> {
    if (this.connectionManager.currentSessionId.length > 0 || this.isConnecting() ||
      this.state.connectionState === RealtimeConnectionState.DISCONNECTING) {
      throw this.reportError(new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Disconnect realtime before stopping the local camera stream'
      ));
    }

    await this.observeError(this.mediaController.stopLocalCameraStream());
  }

  /**
   * 切换当前相机流使用的前后置摄像头。
   *
   * @returns 摄像头切换后的本地媒体流。
   */
  async switchCamera(): Promise<RealtimeMediaStream> {
    if (this.isConnecting()) {
      throw this.reportError(new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Camera switching is unavailable while realtime is connecting'
      ));
    }

    return this.observeError(this.mediaController.switchCamera());
  }

  /**
   * 从本地视频文件创建并启动媒体流。
   *
   * @param filePath 本地视频文件路径。
   * @param videoFormat 可选的视频输出格式；未传入时根据文件信息计算。
   * @returns 当前 Manager 持有的本地视频媒体流。
   */
  async createLocalVideoStream(
    filePath: string,
    videoFormat?: RealtimeVideoFormat
  ): Promise<RealtimeMediaStream> {
    if (this.connectionManager.currentSessionId.length > 0 || this.isConnecting() ||
      this.state.connectionState === RealtimeConnectionState.DISCONNECTING) {
      throw this.reportError(new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Local video stream is unavailable during a realtime connection'
      ));
    }

    return this.observeError(this.mediaController.createLocalVideoStream(
      filePath,
      videoFormat
    ));
  }

  /**
   * 停止本地视频文件流并释放对应预览资源。
   *
   * @returns 停止操作完成后的 Promise。
   */
  async stopLocalVideoStream(): Promise<void> {
    if (this.connectionManager.currentSessionId.length > 0 || this.isConnecting() ||
      this.state.connectionState === RealtimeConnectionState.DISCONNECTING) {
      throw this.reportError(new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Disconnect realtime before stopping the local video stream'
      ));
    }

    await this.observeError(this.mediaController.stopLocalVideoStream());
  }

  /**
   * 从图片输入创建持续输出帧的媒体流。
   *
   * @param source 本地文件路径、图片编码数据或平台 PixelMap。
   * @param videoFormat 可选的视频输出格式；未传入时根据图片信息计算。
   * @returns 当前 Manager 持有的本地图片媒体流。
   */
  async createLocalImageStream(
    source: string | ArrayBuffer | Uint8Array | image.PixelMap,
    videoFormat?: RealtimeVideoFormat
  ): Promise<RealtimeMediaStream> {
    if (this.connectionManager.currentSessionId.length > 0 || this.isConnecting() ||
      this.state.connectionState === RealtimeConnectionState.DISCONNECTING) {
      throw this.reportError(new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Local image stream is unavailable during a realtime connection'
      ));
    }

    return this.observeError(this.mediaController.createLocalImageStream(
      source,
      videoFormat
    ));
  }

  /**
   * 停止本地图片流并释放对应预览资源。
   *
   * @returns 停止操作完成后的 Promise。
   */
  async stopLocalImageStream(): Promise<void> {
    if (this.connectionManager.currentSessionId.length > 0 || this.isConnecting() ||
      this.state.connectionState === RealtimeConnectionState.DISCONNECTING) {
      throw this.reportError(new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Disconnect realtime before stopping the local image stream'
      ));
    }

    await this.observeError(this.mediaController.stopLocalImageStream());
  }

  /**
   * 使用当前 Manager 创建的本地流建立实时连接。
   *
   * @param localStream 已创建并处于活动状态的本地媒体流。
   * @returns 连接建立后用于显示生成结果的远端媒体流。
   */
  async connect(localStream: RealtimeMediaStream): Promise<RealtimeMediaStream> {
    if (this.connectionManager.currentSessionId.length > 0 || this.isConnecting() ||
      this.state.connectionState === RealtimeConnectionState.DISCONNECTING) {
      throw this.reportError(new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Realtime connection is already open'
      ));
    }

    const track: RealtimeVideoTrack | undefined = localStream.videoTrack;
    const videoFormat: RealtimeVideoFormat | undefined = track?.videoFormat;
    if (track === undefined || videoFormat === undefined ||
      !this.mediaController.owns(localStream)) {
      throw this.reportError(new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'The local stream must be created and started by this realtime manager'
      ));
    }

    this.generationManager.reset();
    const operationVersion: number = ++this.operationVersion;
    this.emitState(new RealtimeState(RealtimeConnectionState.CONNECTING));

    try {
      const remoteStream: RealtimeMediaStream = await this.connectionManager.connect(
        this.options.model.name,
        videoFormat,
        this.mediaController.hasAudio,
        (): boolean => this.isOperationCurrent(operationVersion),
        async (
          sessionId: string,
          error: XmaxError
        ): Promise<void> => {
          await this.handleHeartbeatFailure(sessionId, error);
        }
      );

      const sessionId: string = this.connectionManager.currentSessionId;
      if (sessionId.length === 0) {
        throw new XmaxError(XmaxErrorCode.CANCELLED, 'Realtime connection was cancelled');
      }

      this.emitState(new RealtimeState(RealtimeConnectionState.CONNECTED, sessionId));
      this.ensureOperation(operationVersion);

      return remoteStream;
    } catch (error) {
      if (!this.isOperationCurrent(operationVersion)) {
        throw new XmaxError(XmaxErrorCode.CANCELLED, 'Realtime connection was cancelled');
      }

      const xmaxError: XmaxError = this.reportError(error);
      this.emitState(new RealtimeState(RealtimeConnectionState.ERROR));

      throw xmaxError;
    }
  }

  /**
   * 断开当前实时连接并清理生成和房间资源。
   *
   * @returns 连接终止完成后的 Promise；重复调用时返回同一个终止任务。
   */
  disconnect(): Promise<void> {
    if (this.terminationPromise !== null) {
      this.terminationFinalState = RealtimeConnectionState.DISCONNECTED;
      return this.terminationPromise;
    }
    if (this.state.connectionState === RealtimeConnectionState.IDLE ||
      this.state.connectionState === RealtimeConnectionState.DISCONNECTED) {
      return Promise.resolve();
    }

    return this.beginTermination(RealtimeConnectionState.DISCONNECTED);
  }

  /**
   * 开始生成，或在已经生成时更新当前生成条件。
   *
   * @param context 可选的生成条件；首次开始生成时必须提供。
   * @returns 远端结果流确认开始后的 Promise。
   */
  async startGeneration(context?: RealtimeContext): Promise<void> {
    const sessionId: string = this.connectionManager.currentSessionId;
    const videoFormat: RealtimeVideoFormat | undefined =
      this.mediaController.currentVideoFormat;
    const connected: boolean = this.state.connectionState === RealtimeConnectionState.CONNECTED ||
      this.state.connectionState === RealtimeConnectionState.GENERATING;
    if (!connected || sessionId.length === 0 || videoFormat === undefined) {
      throw this.reportError(new XmaxError(
        XmaxErrorCode.RTC_ERROR,
        'Realtime connection is not open'
      ));
    }

    const activeTaskId: string | undefined = this.state.connectionState ===
      RealtimeConnectionState.GENERATING ? this.state.taskId : undefined;
    if (activeTaskId !== undefined) {
      try {
        this.generationManager.update(activeTaskId, videoFormat, context);
      } catch (error) {
        throw this.reportError(error);
      }

      return;
    }

    const operationVersion: number = this.operationVersion;
    this.mediaController.setLocalAudioPreviewEnabled(false);
    try {
      const taskId: string = await this.generationManager.start(
        videoFormat,
        context,
        (): void => {
          this.ensureOperation(operationVersion);
        }
      );
      if (this.connectionManager.currentSessionId !== sessionId) {
        throw new XmaxError(XmaxErrorCode.CANCELLED, 'Realtime connection was cancelled');
      }

      this.emitState(new RealtimeState(
        RealtimeConnectionState.GENERATING,
        sessionId,
        taskId
      ));
    } catch (error) {
      this.mediaController.setLocalAudioPreviewEnabled(true);
      throw this.reportError(error);
    }
  }

  /**
   * 停止当前生成任务并恢复已连接状态。
   *
   * @returns 停止信号发送完成后的 Promise。
   */
  async stopGeneration(): Promise<void> {
    const sessionId: string = this.connectionManager.currentSessionId;
    if (sessionId.length === 0 ||
      (this.state.connectionState !== RealtimeConnectionState.CONNECTED &&
      this.state.connectionState !== RealtimeConnectionState.GENERATING)) {
      return;
    }

    const wasGenerating: boolean =
      this.state.connectionState === RealtimeConnectionState.GENERATING;
    try {
      this.generationManager.stop(this.state.taskId ?? '');
      this.mediaController.setLocalAudioPreviewEnabled(true);
      if (wasGenerating) {
        this.emitState(new RealtimeState(
          RealtimeConnectionState.CONNECTED,
          sessionId
        ));
      }
    } catch (error) {
      throw this.reportError(error);
    }
  }

  /**
   * 在允许的生命周期状态下更新相机来源并同步连接配置。
   *
   * @param update 更新相机媒体流的操作。
   * @returns 更新完成后的本地相机媒体流。
   */
  private async updateLocalCameraStream(
    update: () => Promise<RealtimeMediaStream>
  ): Promise<RealtimeMediaStream> {
    if (this.isConnecting() ||
      this.state.connectionState === RealtimeConnectionState.DISCONNECTING) {
      throw this.reportError(new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Local camera update is unavailable while realtime is transitioning'
      ));
    }
    if (this.connectionManager.currentSessionId.length > 0) {
      await this.stopGeneration();
    }

    const stream: RealtimeMediaStream = await this.observeError(update());
    const videoFormat: RealtimeVideoFormat | undefined = stream.videoTrack?.videoFormat;
    if (videoFormat === undefined) {
      throw this.reportError(new XmaxError(
        XmaxErrorCode.RTC_ERROR,
        'The updated local camera stream does not contain a video format'
      ));
    }

    if (this.connectionManager.currentSessionId.length > 0) {
      try {
        this.streamController.setLocalAudioEnabled(this.mediaController.hasAudio);
      } catch (error) {
        this.reportError(error);
      }

      this.connectionManager.updateRemoteVideoFormat(videoFormat);
    }

    return stream;
  }

  /**
   * 保存并发布新的实时状态。
   *
   * @param state 新的实时状态。
   * @returns 无返回值。
   */
  private emitState(state: RealtimeState): void {
    this.state = state;
    this.notifyStateListener(state);
  }

  /**
   * 安全调用当前状态监听器。
   *
   * @param state 需要通知给接入方的实时状态。
   * @returns 无返回值。
   */
  private notifyStateListener(state: RealtimeState): void {
    const listener: RealtimeStateListener | null = this.stateListener;
    if (listener === null) {
      return;
    }

    try {
      listener(state);
    } catch (error) {
      const reason: string = error instanceof Error ? error.message : String(error);
      XmaxLogger.error(
        `实时状态监听器执行失败\n└─ 原因：${reason}`,
        'Realtime'
      );
    }
  }

  /** @returns 当前是否处于实时连接建立阶段。 */
  private isConnecting(): boolean {
    return this.state.connectionState === RealtimeConnectionState.CONNECTING;
  }

  /**
   * 判断异步操作是否仍属于当前生命周期版本。
   *
   * @param operationVersion 操作启动时记录的生命周期版本。
   * @returns 版本仍然有效时返回 `true`。
   */
  private isOperationCurrent(operationVersion: number): boolean {
    return operationVersion === this.operationVersion;
  }

  /**
   * 确保异步操作仍然有效，过期时抛出取消错误。
   *
   * @param operationVersion 操作启动时记录的生命周期版本。
   * @returns 无返回值。
   */
  private ensureOperation(operationVersion: number): void {
    if (!this.isOperationCurrent(operationVersion)) {
      throw new XmaxError(XmaxErrorCode.CANCELLED, 'Realtime connection was cancelled');
    }
  }

  /**
   * 创建或复用实时连接终止任务。
   *
   * @param finalState 清理成功后需要发布的最终状态。
   * @param fallbackSessionId 当前连接资源已经丢失时使用的会话标识。
   * @returns 实时连接终止完成后的 Promise。
   */
  private beginTermination(
    finalState: RealtimeConnectionState,
    fallbackSessionId?: string
  ): Promise<void> {
    if (this.terminationPromise !== null) {
      if (finalState === RealtimeConnectionState.DISCONNECTED) {
        this.terminationFinalState = finalState;
      }

      return this.terminationPromise;
    }

    this.operationVersion++;
    this.mediaController.setLocalAudioPreviewEnabled(true);
    this.terminationFinalState = finalState;
    const taskId: string = this.state.taskId ?? '';
    const terminationPromise: Promise<void> = Promise.resolve().then(
      (): Promise<void> => this.terminateConnection(
        taskId,
        fallbackSessionId
      )
    );
    this.terminationPromise = terminationPromise;
    this.emitState(new RealtimeState(RealtimeConnectionState.DISCONNECTING));

    return terminationPromise;
  }

  /**
   * 依次清理生成任务、房间连接和服务端会话。
   *
   * @param taskId 终止前仍处于活动状态的生成任务标识。
   * @param fallbackSessionId 当前连接资源已经丢失时使用的会话标识。
   * @returns 全部终止步骤完成后的 Promise。
   */
  private async terminateConnection(
    taskId: string,
    fallbackSessionId?: string
  ): Promise<void> {
    const activeSessionId: string = this.connectionManager.currentSessionId;
    let sessionId: string | undefined = fallbackSessionId ??
      (activeSessionId.length > 0 ? activeSessionId : undefined);
    let terminationError: XmaxError | null = null;

    try {
      this.generationManager.reset(taskId);
    } catch (error) {
      const reason: string = error instanceof Error ? error.message : String(error);
      XmaxLogger.error(
        `重置生成任务失败\n└─ 原因：${reason}`,
        'Realtime'
      );
    }

    try {
      const disconnectedSessionId: string | undefined =
        await this.connectionManager.disconnect(fallbackSessionId);
      sessionId = disconnectedSessionId ?? sessionId;
    } catch (error) {
      terminationError = this.reportError(error);
    } finally {
      let finalState: RealtimeConnectionState = this.terminationFinalState ??
        RealtimeConnectionState.ERROR;
      if (terminationError !== null) {
        finalState = RealtimeConnectionState.ERROR;
      }

      this.terminationPromise = null;
      this.terminationFinalState = null;
      this.emitState(new RealtimeState(finalState, sessionId));
    }

    if (terminationError !== null) {
      throw terminationError;
    }
  }

  /**
   * 处理房间心跳失败并终止对应的实时连接。
   *
   * @param sessionId 发生心跳错误的会话标识。
   * @param error 心跳请求产生的错误。
   * @returns 错误上报和连接终止完成后的 Promise。
   */
  private async handleHeartbeatFailure(
    sessionId: string,
    error: XmaxError
  ): Promise<void> {
    if (this.connectionManager.currentSessionId !== sessionId) {
      return;
    }

    this.errorManager.handle(error);
    await this.beginTermination(RealtimeConnectionState.ERROR, sessionId);
  }

  /**
   * 观察异步操作并将失败统一转换和上报为 `XmaxError`。
   *
   * @param operation 需要观察的异步操作。
   * @returns 原异步操作成功返回的结果。
   */
  private async observeError<T>(operation: Promise<T>): Promise<T> {
    try {
      return await operation;
    } catch (error) {
      throw this.reportError(error);
    }
  }

  /**
   * 将错误交给统一错误组件记录并通知接入方。
   *
   * @param error 待处理的错误对象。
   * @returns 规范化后的 `XmaxError`。
   */
  private reportError(error: Object): XmaxError {
    return this.errorManager.handle(XmaxError.from(error));
  }
}
