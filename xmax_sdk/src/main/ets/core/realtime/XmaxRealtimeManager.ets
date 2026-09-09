import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import {
  XmaxError,
  XmaxErrorCode,
  XmaxErrorSeverity
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
  RealtimeDisconnectionReason,
  RealtimeState,
  RealtimeStateListener
} from '../../service/realtime/RealtimeState';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import { StreamController } from '../../stream/StreamController';
import { StreamControlling } from '../../stream/StreamControlling';
import { MediaService } from '../../service/media/MediaService';
import { RealtimeMediaSource } from './RealtimeMediaSource';
import { RealtimeTiming, RealtimeTimingRun } from './RealtimeTiming';
import { RealtimeConfiguration } from './RealtimeConfiguration';
import {
  RealtimeCoordinator,
  RealtimeOperationKind,
  RealtimeOperationToken,
  RealtimeTerminationScope
} from './RealtimeCoordinator';
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

  private readonly timing: RealtimeTiming = new RealtimeTiming();

  // 生命周期协调
  private readonly coordinator: RealtimeCoordinator;

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
    this.renderController = new RenderController(this.rtcManager, (error: XmaxError): void => {
      if (error.severity === XmaxErrorSeverity.FATAL) {
        this.renderController.failRemoteFrameWait(error);
      }
      this.errorManager.handle(error);
    });

    // 业务层组件
    this.streamController = new StreamController(
      this.rtcManager,
      (stream): void => {
        this.renderController.setRemoteStream(stream);
      },
      (error: XmaxError): void => {
        if (error.severity === XmaxErrorSeverity.FATAL) {
          this.renderController.failRemoteFrameWait(error);
        }
        this.errorManager.handle(error);
      },
      this.timing
    );
    this.mediaController = new MediaController(
      context,
      this.rtcManager,
      this.streamController,
      (error: XmaxError): void => {
        if (error.severity === XmaxErrorSeverity.FATAL) {
          this.renderController.failRemoteFrameWait(error);
        }
        this.errorManager.handle(error);
      },
      new MediaService(options.model),
      (format: RealtimeVideoFormat): void => {
        this.handleCameraVideoFormatChange(format);
      }
    );

    // 实时管理组件
    this.connectionManager = new XmaxRealtimeConnectionManager(
      apiService,
      this.mediaController,
      this.renderController,
      this.streamController,
      this.timing
    );
    this.generationManager = new XmaxRealtimeGenerationManager(
      this.mediaController,
      this.streamController
    );
    this.coordinator = new RealtimeCoordinator(this.errorManager,
      (scope: RealtimeTerminationScope, taskId: string): Promise<string | undefined> =>
        this.cleanup(scope, taskId));
  }

  /** @returns 当前实时连接与生成状态。 */
  get currentState(): RealtimeState {
    return this.coordinator.currentState;
  }

  /**
   * 设置实时连接状态监听器。
   *
   * @param listener 状态监听器；传入空值时清除监听器。
   * @returns 无返回值。
   */
  setStateListener(listener: RealtimeStateListener | null): void {
    this.coordinator.setStateListener(listener);
  }

  /**
   * 设置实时致命错误监听器；可恢复错误由具体调用返回。
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

  /** @inheritdoc */
  async setLocalAudioVolume(volume: number): Promise<void> {
    try {
      this.validateAudioVolume(volume);
      await this.mediaController.setLocalAudioVolume(volume);
    } catch (error) {
      throw this.reportError(XmaxError.from(error).withSeverity(XmaxErrorSeverity.RECOVERABLE));
    }
  }

  /** @inheritdoc */
  async setRemoteAudioVolume(volume: number): Promise<void> {
    try {
      this.validateAudioVolume(volume);
      this.streamController.setRemoteAudioVolume(volume);
    } catch (error) {
      throw this.reportError(XmaxError.from(error).withSeverity(XmaxErrorSeverity.RECOVERABLE));
    }
  }

  private validateAudioVolume(volume: number): void {
    if (!Number.isFinite(volume) || volume < 0 || volume > 1) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Audio volume must be between 0 and 1'
      );
    }
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

  /** 创建并启动本地相机流。 */
  async createLocalCameraStream(
    videoFormat: RealtimeVideoFormat = this.options.model.defaultCameraVideoFormat,
    position: CameraPosition = CameraPosition.FRONT
  ): Promise<RealtimeMediaStream> {
    this.validateMediaSource(RealtimeMediaSource.CAMERA);
    return this.coordinator.run(RealtimeOperationKind.MEDIA, RealtimeTerminationScope.ALL,
      async (token: RealtimeOperationToken): Promise<RealtimeMediaStream> => {
        this.ensureLocalMediaCanChange();
        const stream = await this.mediaController.createLocalCameraStream(videoFormat, position);
        token.ensureCurrent();
        return stream;
      });
  }

  /** 停止本地相机流并释放预览资源。 */
  stopLocalCameraStream(): Promise<void> {
    return this.coordinator.run(RealtimeOperationKind.MEDIA, RealtimeTerminationScope.ALL,
      async (token: RealtimeOperationToken): Promise<void> => {
        this.ensureLocalMediaCanChange();
        await this.mediaController.stopLocalCameraStream();
        token.ensureCurrent();
      });
  }

  /** 切换摄像头，生成中切换时保留连接并恢复当前生成条件。 */
  switchCamera(): Promise<RealtimeMediaStream> {
    return this.coordinator.run(RealtimeOperationKind.CAMERA_SWITCH, RealtimeTerminationScope.CONNECTION,
      async (token: RealtimeOperationToken): Promise<RealtimeMediaStream> => {
        const current: RealtimeState = this.currentState;
        const wasGenerating: boolean = current.connectionState === RealtimeConnectionState.GENERATING;
        if (current.connectionState === RealtimeConnectionState.CONNECTING ||
          current.connectionState === RealtimeConnectionState.DISCONNECTING ||
          (!wasGenerating && this.streamController.currentGenerationTaskId.length > 0)) {
          throw new XmaxError(XmaxErrorCode.INVALID_CONFIGURATION,
            'Camera switching is unavailable while realtime is transitioning');
        }
        if (wasGenerating) {
          this.generationManager.stop(current.taskId ?? '');
          this.restoreLocalAudioPreview();
          this.coordinator.commit(new RealtimeState(RealtimeConnectionState.CONNECTED, current.sessionId), token);
        }
        const stream: RealtimeMediaStream = await this.mediaController.switchCamera();
        token.ensureCurrent();
        if (wasGenerating) {
          await token.delay(500);
          await this.performStartGeneration(undefined, token);
        }
        return stream;
      });
  }

  /** 从本地视频文件创建并启动媒体流，使用当前模型的输入规则。 */
  async createLocalVideoStream(filePath: string, videoFormat?: RealtimeVideoFormat): Promise<RealtimeMediaStream> {
    this.validateMediaSource(RealtimeMediaSource.VIDEO);
    return this.coordinator.run(RealtimeOperationKind.MEDIA, RealtimeTerminationScope.ALL,
      async (token: RealtimeOperationToken): Promise<RealtimeMediaStream> => {
        this.ensureLocalMediaCanChange();
        const stream = await this.mediaController.createLocalVideoStream(filePath, videoFormat);
        token.ensureCurrent();
        return stream;
      });
  }

  /** 停止本地视频流并释放预览资源。 */
  stopLocalVideoStream(): Promise<void> {
    return this.coordinator.run(RealtimeOperationKind.MEDIA, RealtimeTerminationScope.ALL,
      async (token: RealtimeOperationToken): Promise<void> => {
        this.ensureLocalMediaCanChange();
        await this.mediaController.stopLocalVideoStream();
        token.ensureCurrent();
      });
  }

  /** 从图片输入创建持续输出帧的媒体流。 */
  async createLocalImageStream(
    source: string | ArrayBuffer | Uint8Array | image.PixelMap,
    videoFormat?: RealtimeVideoFormat
  ): Promise<RealtimeMediaStream> {
    this.validateMediaSource(RealtimeMediaSource.IMAGE);
    return this.coordinator.run(RealtimeOperationKind.MEDIA, RealtimeTerminationScope.ALL,
      async (token: RealtimeOperationToken): Promise<RealtimeMediaStream> => {
        this.ensureLocalMediaCanChange();
        const stream = await this.mediaController.createLocalImageStream(source, videoFormat);
        token.ensureCurrent();
        return stream;
      });
  }

  /** 停止本地图片流并释放预览资源。 */
  stopLocalImageStream(): Promise<void> {
    return this.coordinator.run(RealtimeOperationKind.MEDIA, RealtimeTerminationScope.ALL,
      async (token: RealtimeOperationToken): Promise<void> => {
        this.ensureLocalMediaCanChange();
        await this.mediaController.stopLocalImageStream();
        token.ensureCurrent();
      });
  }

  /** 使用当前 Manager 创建的本地流建立实时连接。 */
  connect(localStream: RealtimeMediaStream): Promise<RealtimeMediaStream> {
    return this.coordinator.run(RealtimeOperationKind.CONNECTION, RealtimeTerminationScope.CONNECTION,
      (token: RealtimeOperationToken): Promise<RealtimeMediaStream> => this.performConnect(localStream, token));
  }

  private async performConnect(localStream: RealtimeMediaStream,
    token: RealtimeOperationToken): Promise<RealtimeMediaStream> {
    token.ensureCurrent();
    const current: RealtimeState = this.currentState;
    if (this.connectionManager.currentSessionId.length > 0 ||
      current.connectionState === RealtimeConnectionState.CONNECTING ||
      current.connectionState === RealtimeConnectionState.DISCONNECTING) {
      throw new XmaxError(XmaxErrorCode.INVALID_CONFIGURATION, 'Realtime connection is already open');
    }
    const videoFormat: RealtimeVideoFormat | undefined = localStream.videoTrack?.videoFormat;
    if (videoFormat === undefined || !this.mediaController.owns(localStream)) {
      throw new XmaxError(XmaxErrorCode.INVALID_CONFIGURATION,
        'The local stream must be created and started by this realtime manager');
    }
    this.generationManager.reset();
    this.coordinator.commit(new RealtimeState(RealtimeConnectionState.CONNECTING), token);
    const remoteStream: RealtimeMediaStream = await this.connectionManager.connect(
      this.options.model.name, videoFormat, this.mediaController.hasAudio,
      (): boolean => token.isCurrent,
      (sessionId: string, error: XmaxError): Promise<void> => this.handleHeartbeatFailure(sessionId, error));
    token.ensureCurrent();
    const sessionId: string = this.connectionManager.currentSessionId;
    if (sessionId.length === 0) {
      throw RealtimeOperationToken.cancelledError();
    }
    this.coordinator.commit(new RealtimeState(RealtimeConnectionState.CONNECTED, sessionId), token);
    return remoteStream;
  }

  private handleCameraVideoFormatChange(format: RealtimeVideoFormat): void {
    const current: RealtimeConnectionState = this.currentState.connectionState;
    if (current === RealtimeConnectionState.DISCONNECTING) {
      return;
    }
    const previous: RealtimeVideoFormat | undefined = this.mediaController.currentVideoFormat;
    const orientationChanged: boolean = previous !== undefined &&
      (previous.width > previous.height) !== (format.width > format.height);
    if (orientationChanged && (current === RealtimeConnectionState.GENERATING ||
      current === RealtimeConnectionState.CONNECTING ||
      this.coordinator.hasOperation(RealtimeOperationKind.GENERATION) ||
      this.coordinator.hasOperation(RealtimeOperationKind.CAMERA_SWITCH))) {
      // 在新方向的帧进入生成链路前取消操作，不向旧任务发送尺寸更新。
      void this.coordinator.terminate(RealtimeTerminationScope.CONNECTION,
        RealtimeConnectionState.DISCONNECTED, RealtimeDisconnectionReason.CAMERA_ORIENTATION_CHANGED)
        .catch((error: Object): void => this.logCleanupFailure('相机转屏后断开实时连接失败', error));
      try {
        this.generationManager.reset();
      } catch (error) {
        this.logCleanupFailure('相机转屏后停止生成失败', error);
      }
      return;
    }
    this.generationManager.updateVideoFormat(format);
    this.connectionManager.updateVideoFormat(format);
  }

  /** 取消连接/生成，等待回滚和清理完成，保留本地媒体与预览。 */
  disconnect(): Promise<void> {
    const current: RealtimeState = this.currentState;
    if ((current.connectionState === RealtimeConnectionState.IDLE ||
      current.connectionState === RealtimeConnectionState.DISCONNECTED) &&
      !this.coordinator.hasOperation(RealtimeOperationKind.CONNECTION) &&
      !this.coordinator.hasOperation(RealtimeOperationKind.GENERATION)) {
      return Promise.resolve();
    }
    return this.coordinator.terminate(RealtimeTerminationScope.CONNECTION, RealtimeConnectionState.DISCONNECTED);
  }

  /** 立即静默媒体，等待进行中的操作结束后释放所有实时资源。 */
  close(): Promise<void> {
    const wasClosing: boolean = this.coordinator.isClosing;
    const closing: Promise<void> = this.coordinator.terminate(
      RealtimeTerminationScope.ALL, RealtimeConnectionState.DISCONNECTED);
    if (!wasClosing) {
      try {
        this.mediaController.setLocalAudioPreviewEnabled(false);
        this.mediaController.prepareForClose();
      } catch (error) {
        this.logCleanupFailure('静默本地媒体失败', error);
      }
      this.connectionManager.prepareForClose();
    }
    return closing;
  }

  /** 开始生成；生成中再次调用则更新条件。传入本地流时按需建立连接。 */
  startGeneration(context?: RealtimeContext): Promise<void>;
  startGeneration(localStream: RealtimeMediaStream, context?: RealtimeContext): Promise<RealtimeMediaStream>;
  startGeneration(input?: RealtimeContext | RealtimeMediaStream,
    context?: RealtimeContext): Promise<void | RealtimeMediaStream> {
    const scope: RealtimeTerminationScope = input instanceof RealtimeMediaStream &&
      this.connectionManager.currentSessionId.length === 0 ?
      RealtimeTerminationScope.CONNECTION : RealtimeTerminationScope.GENERATION;
    let measurement: RealtimeTimingRun | null = null;
    const operation = this.coordinator.run<void | RealtimeMediaStream>(RealtimeOperationKind.GENERATION, scope,
      async (token: RealtimeOperationToken): Promise<void | RealtimeMediaStream> => {
        // 只在获得操作所有权后开始计时；更新条件与被拒绝的并发调用不重置统计。
        if (this.currentState.connectionState !== RealtimeConnectionState.GENERATING) {
          measurement = this.timing.begin();
        }
        try {
          if (input instanceof RealtimeMediaStream) {
            return await this.startGenerationWithStream(input, context, token);
          }
          await this.performStartGeneration(input, token);
        } finally {
          this.timing.endOperation(measurement);
        }
      });
    return operation.catch((error: Object): void | RealtimeMediaStream => {
      // Coordinator 已完成取消或错误清理；使用该操作的记录，避免影响较新的重试。
      this.timing.finishFailure(error, measurement);
      throw XmaxError.from(error);
    });
  }

  private async startGenerationWithStream(localStream: RealtimeMediaStream, context: RealtimeContext | undefined,
    token: RealtimeOperationToken): Promise<RealtimeMediaStream> {
    if (!this.mediaController.owns(localStream)) {
      throw new XmaxError(XmaxErrorCode.INVALID_CONFIGURATION,
        'The local stream must be created and started by this realtime manager');
    }
    let remoteStream: RealtimeMediaStream;
    if (this.connectionManager.currentSessionId.length > 0) {
      const activeRemoteStream: RealtimeMediaStream | null = this.connectionManager.currentRemoteStream;
      if (activeRemoteStream === null) {
        throw new XmaxError(XmaxErrorCode.RTC_ERROR, 'Realtime connection has no remote stream');
      }
      remoteStream = activeRemoteStream;
    } else {
      if (context === undefined) {
        throw new XmaxError(XmaxErrorCode.INVALID_CONFIGURATION,
          'A realtime context is required for the first generation');
      }
      this.mediaController.setLocalAudioPreviewEnabled(false);
      remoteStream = await this.performConnect(localStream, token);
      token.setFailureScope(RealtimeTerminationScope.GENERATION);
    }
    token.ensureCurrent();
    await this.performStartGeneration(context, token);
    return remoteStream;
  }

  private async performStartGeneration(context: RealtimeContext | undefined,
    token: RealtimeOperationToken): Promise<void> {
    token.ensureCurrent();
    const sessionId: string = this.connectionManager.currentSessionId;
    const videoFormat: RealtimeVideoFormat | undefined = this.mediaController.currentVideoFormat;
    let current: RealtimeState = this.currentState;
    if (current.connectionState === RealtimeConnectionState.ERROR && sessionId.length > 0) {
      current = new RealtimeState(RealtimeConnectionState.CONNECTED, sessionId);
      this.coordinator.commit(current, token);
    }
    if (sessionId.length === 0 || videoFormat === undefined ||
      (current.connectionState !== RealtimeConnectionState.CONNECTED &&
      current.connectionState !== RealtimeConnectionState.GENERATING)) {
      throw new XmaxError(XmaxErrorCode.RTC_ERROR,
        'Realtime connection is not open').withSeverity(XmaxErrorSeverity.RECOVERABLE);
    }
    if (current.connectionState === RealtimeConnectionState.GENERATING && current.taskId !== undefined) {
      this.generationManager.update(current.taskId, videoFormat, context);
      token.ensureCurrent();
      return;
    }
    this.mediaController.setLocalAudioPreviewEnabled(false);
    try {
      const taskId: string = await this.generationManager.start(videoFormat, context,
        (): void => token.ensureCurrent(),
        (confirmation: Promise<void>): Promise<void> => token.wait(confirmation));
      token.ensureCurrent();
      await token.wait(this.renderController.waitUntilRemoteFrameReady());
      token.ensureCurrent();
      this.streamController.activateRemoteAudio();
      if (this.connectionManager.currentSessionId !== sessionId) {
        throw RealtimeOperationToken.cancelledError();
      }
      this.coordinator.commit(new RealtimeState(RealtimeConnectionState.GENERATING, sessionId, taskId), token);
      this.timing.finish(taskId);
    } catch (error) {
      this.restoreLocalAudioPreview();
      throw XmaxError.from(error);
    }
  }

  /** 已连接时停止当前或尚在启动的生成，保留连接；其他状态直接返回。 */
  stopGeneration(): Promise<void> {
    const current: RealtimeState = this.currentState;
    if (this.connectionManager.currentSessionId.length === 0 ||
      (current.connectionState !== RealtimeConnectionState.CONNECTED &&
      current.connectionState !== RealtimeConnectionState.GENERATING)) {
      return Promise.resolve();
    }
    return this.coordinator.terminate(RealtimeTerminationScope.GENERATION);
  }

  /** 在分配媒体资源之前拒绝模型不支持的来源，保留当前媒体与状态。 */
  private validateMediaSource(source: RealtimeMediaSource): void {
    if (!this.options.model.supportedMediaSources.has(source)) {
      throw this.reportError(new XmaxError(XmaxErrorCode.INVALID_CONFIGURATION,
        `Model ${this.options.model.name} does not support ${source} input`,
        undefined, undefined, XmaxErrorSeverity.RECOVERABLE));
    }
  }

  private ensureLocalMediaCanChange(): void {
    const current: RealtimeState = this.currentState;
    if (this.connectionManager.currentSessionId.length > 0 ||
      current.connectionState === RealtimeConnectionState.CONNECTING ||
      current.connectionState === RealtimeConnectionState.DISCONNECTING) {
      throw new XmaxError(XmaxErrorCode.INVALID_CONFIGURATION,
        'Disconnect realtime before changing the local media stream');
    }
  }

  /** 清理失败只记录日志，继续释放后续资源，保留触发终止的原始错误。 */
  private async cleanup(scope: RealtimeTerminationScope, taskId: string): Promise<string | undefined> {
    try {
      if (scope >= RealtimeTerminationScope.CONNECTION) {
        this.generationManager.reset(taskId);
      } else {
        this.generationManager.stop(taskId);
      }
    } catch (error) {
      this.logCleanupFailure('停止实时生成失败', error);
    }
    let sessionId: string | undefined;
    if (scope >= RealtimeTerminationScope.CONNECTION) {
      sessionId = this.connectionManager.currentSessionId || undefined;
      try {
        sessionId = (await this.connectionManager.disconnect()) ?? sessionId;
      } catch (error) {
        this.logCleanupFailure('断开实时连接失败', error);
      }
    }
    if (scope === RealtimeTerminationScope.ALL) {
      try {
        await this.mediaController.stopLocalStream();
      } catch (error) {
        this.logCleanupFailure('关闭本地媒体失败', error);
      }
    } else {
      this.restoreLocalAudioPreview();
    }
    return sessionId;
  }

  private restoreLocalAudioPreview(): void {
    if (!this.coordinator.isClosing) {
      this.mediaController.setLocalAudioPreviewEnabled(true);
    }
  }

  private handleHeartbeatFailure(sessionId: string, error: XmaxError): Promise<void> {
    if (this.connectionManager.currentSessionId !== sessionId) {
      return Promise.resolve();
    }
    return this.coordinator.terminateWithError(error, RealtimeTerminationScope.CONNECTION);
  }

  private logCleanupFailure(title: string, error: Object): void {
    XmaxLogger.error(`${title}\n└─ 原因：${XmaxError.from(error).message}`, 'Realtime');
  }

  private reportError(error: Object): XmaxError {
    return this.errorManager.handle(XmaxError.from(error));
  }
}
