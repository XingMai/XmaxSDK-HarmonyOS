import { RealtimeVideoTrack, setRealtimeVideoTrackOrientationHandler, updateRealtimeVideoTrackOrientation } from '../../service/realtime/RealtimeVideoTrack';
import { RealtimeVideoFrameListener } from '../../service/realtime/RealtimeVideoFrame';
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
import { RealtimeContext } from '../../service/realtime/RealtimeContext';
import { RealtimeMediaStream } from '../../service/realtime/RealtimeMediaStream';
import { RealtimeNetworkQualityListener } from '../../service/realtime/RealtimeNetworkQuality';
import { RealtimePerformanceAlarmListener } from '../../service/realtime/RealtimePerformanceAlarm';
import {
  RealtimeConnectionState,
  RealtimeReason,
  RealtimeState,
  RealtimeStateListener
} from '../../service/realtime/RealtimeState';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import { StreamController } from '../../stream/StreamController';
import { StreamControlling } from '../../stream/StreamControlling';
import { MediaService } from '../../service/media/MediaService';
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

  /** 转屏重启的采集稳定等待定时器挂起标志，避免重复调度。 */
  private orientationRestartPending: boolean = false;

  /** 转屏重启重新提交的操作句柄；非空时用户新条件并入该任务而不是新建操作。 */
  private orientationRestartCompletion: Promise<void> | null = null;

  /** 当前生成任务提交时使用的视频格式，用于发现确认等待期的方向漂移。 */
  private lastSubmittedFormat: RealtimeVideoFormat | undefined = undefined;

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
      this.handleRuntimeError(error, RealtimeTerminationScope.CONNECTION);
    });

    // 业务层组件
    this.streamController = new StreamController(
      this.rtcManager,
      (stream): void => {
        this.renderController.setRemoteStream(stream);
      },
      (error: XmaxError): void => {
        this.handleRuntimeError(error, RealtimeTerminationScope.CONNECTION);
      },
      this.timing
    );
    this.mediaController = new MediaController(
      context,
      this.rtcManager,
      this.streamController,
      (error: XmaxError): void => {
        this.handleRuntimeError(error, RealtimeTerminationScope.ALL);
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
        this.cleanup(scope, taskId),
      (): boolean => this.mediaController.currentTrack !== null);
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


  /** @inheritdoc */
  setRemoteVideoFrameListener(listener: RealtimeVideoFrameListener | null): void {
    try {
      this.renderController.setRemoteVideoFrameListener(listener);
    } catch (error) {
      throw this.reportError(XmaxError.from(error));
    }
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
  get localAudioVolume(): number {
    return this.mediaController.localAudioVolume;
  }

  /** @inheritdoc */
  async setLocalAudioVolume(volume: number): Promise<void> {
    try {
      this.validateAudioVolume(volume);
      await this.mediaController.setLocalAudioVolume(volume);
    } catch (error) {
      throw this.reportError(XmaxError.from(error));
    }
  }

  /** @inheritdoc */
  get remoteAudioVolume(): number {
    return this.streamController.remoteAudioVolume;
  }

  /** @inheritdoc */
  async setRemoteAudioVolume(volume: number): Promise<void> {
    try {
      this.validateAudioVolume(volume);
      this.streamController.setRemoteAudioVolume(volume);
    } catch (error) {
      throw this.reportError(XmaxError.from(error));
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


  /** 创建并启动本地相机流。 */
  async createLocalCameraStream(
    videoFormat: RealtimeVideoFormat = this.options.model.defaultCameraVideoFormat,
    position: CameraPosition = CameraPosition.FRONT,
    useMicrophone: boolean = false,
    observeDisplayChange: boolean = true
  ): Promise<RealtimeMediaStream> {
    return this.coordinator.run(RealtimeOperationKind.MEDIA, null,
      async (token: RealtimeOperationToken): Promise<RealtimeMediaStream> => {
        this.ensureLocalMediaCanChange();
        if (this.mediaController.currentTrack !== null) {
          throw new XmaxError(XmaxErrorCode.INVALID_CONFIGURATION, 'Stop the current local stream before creating another one');
        }
        this.mediaController.setCameraPreviewReadyHandler(null);
        this.coordinator.commit(new RealtimeState(RealtimeConnectionState.PREPARING), token);
        const stream = await this.mediaController.createLocalCameraStream(videoFormat, position, useMicrophone, observeDisplayChange);
        token.ensureCurrent();
        token.setFailureScope(RealtimeTerminationScope.ALL);
        if (observeDisplayChange) {
          this.observeLocalOrientation(stream);
        }
        this.streamController.setRemoteAudioVolume(0);
        this.mediaController.setCameraPreviewReadyHandler((): void => {
          this.coordinator.localPreviewDidBecomeReady((): boolean =>
            stream.videoTrack !== undefined && this.mediaController.currentTrack === stream.videoTrack);
        });
        return stream;
      });
  }

  /** 停止本地相机流并释放预览资源。 */
  stopLocalCameraStream(): Promise<void> {
    return this.coordinator.run(RealtimeOperationKind.MEDIA, null,
      async (token: RealtimeOperationToken): Promise<void> => {
        this.ensureLocalMediaCanChange();
        token.setFailureScope(RealtimeTerminationScope.ALL);
        const track = this.mediaController.currentTrack;
        await this.mediaController.stopLocalCameraStream();
        if (track !== null && this.mediaController.currentTrack !== track) {
          setRealtimeVideoTrackOrientationHandler(track);
        }
        this.coordinator.commit(new RealtimeState(this.mediaController.currentTrack !== null ?
          RealtimeConnectionState.READY : RealtimeConnectionState.IDLE), token);
      });
  }

  /** 切换摄像头，生成中切换时保留连接并恢复当前生成条件。 */
  switchCamera(): Promise<RealtimeMediaStream> {
    const operation: Promise<RealtimeMediaStream> = this.coordinator.run(RealtimeOperationKind.CAMERA_SWITCH, null,
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
          token.setFailureScope(RealtimeTerminationScope.CONNECTION);
          this.renderController.stopRemoteVideoFrameDelivery();
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
    return operation.finally((): void => {
      // 切换的确认等待期转屏时，收尾自检方向漂移并按需重建。
      this.restartGenerationIfOrientationDrifted();
    });
  }

  /** 从本地视频文件创建并启动媒体流，使用当前模型的输入规则。 */
  async createLocalVideoStream(filePath: string, videoFormat?: RealtimeVideoFormat): Promise<RealtimeMediaStream> {
    return this.coordinator.run(RealtimeOperationKind.MEDIA, null,
      async (token: RealtimeOperationToken): Promise<RealtimeMediaStream> => {
        this.ensureLocalMediaCanChange();
        if (this.mediaController.currentTrack !== null) {
          throw new XmaxError(XmaxErrorCode.INVALID_CONFIGURATION, 'Stop the current local stream before creating another one');
        }
        this.mediaController.setCameraPreviewReadyHandler(null);
        this.coordinator.commit(new RealtimeState(RealtimeConnectionState.PREPARING), token);
        const stream = await this.mediaController.createLocalVideoStream(filePath, videoFormat);
        token.ensureCurrent();
        token.setFailureScope(RealtimeTerminationScope.ALL);
        this.observeLocalOrientation(stream);
        this.streamController.setRemoteAudioVolume(1);
        this.coordinator.commit(new RealtimeState(RealtimeConnectionState.READY), token);
        return stream;
      });
  }

  /** 停止本地视频流并释放预览资源。 */
  stopLocalVideoStream(): Promise<void> {
    return this.coordinator.run(RealtimeOperationKind.MEDIA, null,
      async (token: RealtimeOperationToken): Promise<void> => {
        this.ensureLocalMediaCanChange();
        token.setFailureScope(RealtimeTerminationScope.ALL);
        const track = this.mediaController.currentTrack;
        await this.mediaController.stopLocalVideoStream();
        if (track !== null && this.mediaController.currentTrack !== track) {
          setRealtimeVideoTrackOrientationHandler(track);
        }
        this.coordinator.commit(new RealtimeState(this.mediaController.currentTrack !== null ?
          RealtimeConnectionState.READY : RealtimeConnectionState.IDLE), token);
      });
  }

  /** 从图片输入创建持续输出帧的媒体流。 */
  async createLocalImageStream(
    source: string | ArrayBuffer | Uint8Array | image.PixelMap,
    videoFormat?: RealtimeVideoFormat
  ): Promise<RealtimeMediaStream> {
    return this.coordinator.run(RealtimeOperationKind.MEDIA, null,
      async (token: RealtimeOperationToken): Promise<RealtimeMediaStream> => {
        this.ensureLocalMediaCanChange();
        if (this.mediaController.currentTrack !== null) {
          throw new XmaxError(XmaxErrorCode.INVALID_CONFIGURATION, 'Stop the current local stream before creating another one');
        }
        this.mediaController.setCameraPreviewReadyHandler(null);
        this.coordinator.commit(new RealtimeState(RealtimeConnectionState.PREPARING), token);
        const stream = await this.mediaController.createLocalImageStream(source, videoFormat);
        token.ensureCurrent();
        token.setFailureScope(RealtimeTerminationScope.ALL);
        this.observeLocalOrientation(stream);
        this.streamController.setRemoteAudioVolume(0);
        this.coordinator.commit(new RealtimeState(RealtimeConnectionState.READY), token);
        return stream;
      });
  }

  /** 停止本地图片流并释放预览资源。 */
  stopLocalImageStream(): Promise<void> {
    return this.coordinator.run(RealtimeOperationKind.MEDIA, null,
      async (token: RealtimeOperationToken): Promise<void> => {
        this.ensureLocalMediaCanChange();
        token.setFailureScope(RealtimeTerminationScope.ALL);
        const track = this.mediaController.currentTrack;
        await this.mediaController.stopLocalImageStream();
        if (track !== null && this.mediaController.currentTrack !== track) {
          setRealtimeVideoTrackOrientationHandler(track);
        }
        this.coordinator.commit(new RealtimeState(this.mediaController.currentTrack !== null ?
          RealtimeConnectionState.READY : RealtimeConnectionState.IDLE), token);
      });
  }

  /** 使用当前 Manager 创建的本地流建立实时连接。 */
  connect(localStream: RealtimeMediaStream): Promise<RealtimeMediaStream> {
    return this.coordinator.run(RealtimeOperationKind.CONNECTION, null,
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
    if (!this.mediaController.owns(localStream)) {
      throw new XmaxError(XmaxErrorCode.INVALID_CONFIGURATION,
        'The local stream must be created and started by this realtime manager');
    }
    this.mediaController.updateCameraOrientation();
    token.ensureCurrent();
    const videoFormat: RealtimeVideoFormat | undefined = localStream.videoTrack?.videoFormat;
    if (videoFormat === undefined) {
      throw new XmaxError(XmaxErrorCode.INVALID_CONFIGURATION,
        'The local stream must be created and started by this realtime manager');
    }
    token.setFailureScope(RealtimeTerminationScope.CONNECTION);
    this.generationManager.reset();
    this.coordinator.commit(new RealtimeState(RealtimeConnectionState.CONNECTING), token);
    this.mediaController.startMicrophoneCapture();
    token.ensureCurrent();
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

  private observeLocalOrientation(stream: RealtimeMediaStream): void {
    if (stream.videoTrack === undefined) {
      return;
    }
    const track = RealtimeVideoTrack.resolve(stream.videoTrack);
    setRealtimeVideoTrackOrientationHandler(track, (): void => {
      if (this.mediaController.currentTrack === track && !this.coordinator.isClosing) {
        this.handleLocalOrientationChange();
      }
    });
  }

  /** 转屏先同步 Native 方向；相机尺寸翻转后经帧格式变化入口重启生成，其他来源不受影响。 */
  private handleLocalOrientationChange(): void {
    try {
      this.mediaController.updateCameraOrientation();
    } catch (error) {
      this.handleRuntimeError(XmaxError.from(error), RealtimeTerminationScope.ALL);
    }
  }

  /**
   * 转屏重启第一步：检测到方向漂移时用一个短操作停止任务、保留连接并提交 CONNECTED，
   * 随即释放协调器，采集稳定等待由定时器接力。change_condition 无法修改尺寸，方向翻转必须重建任务。
   */
  private restartGenerationIfOrientationDrifted(format?: RealtimeVideoFormat): void {
    // 协调器被用户操作占用时跳过，其收尾的漂移自检会兜底重新触发。
    if (this.orientationRestartPending || this.coordinator.hasActiveOperation() ||
      !this.hasOrientationDrift(format)) {
      return;
    }
    const sessionId: string = this.currentState.sessionId ?? '';
    let stopped: boolean = false;
    const operation: Promise<void | RealtimeMediaStream> = this.coordinator.run(
      RealtimeOperationKind.GENERATION, null,
      async (token: RealtimeOperationToken): Promise<void> => {
        token.setFailureScope(RealtimeTerminationScope.CONNECTION);
        this.renderController.stopRemoteVideoFrameDelivery();
        this.generationManager.stop(this.currentState.taskId ?? '');
        this.restoreLocalAudioPreview();
        this.coordinator.commit(new RealtimeState(RealtimeConnectionState.CONNECTED,
          sessionId, undefined, RealtimeReason.ORIENTATION_CHANGED), token);
        stopped = true;
      });
    void operation.catch((error: Object): void => {
      const resolved: XmaxError = XmaxError.from(error);
      if (resolved.code !== XmaxErrorCode.CANCELLED) {
        this.logCleanupFailure("转屏后停止生成失败 (Failed to Stop Generation after Orientation Change)", resolved);
      }
    }).finally((): void => {
      // 只有停止成功落地才等待重启；被取消时由终止流程或后续自检接管。
      if (stopped) {
        this.scheduleOrientationRestart();
      }
    });
  }

  /**
   * 在协调器外等待采集稳定。等待窗口不占用协调器，用户操作（如更换参考图）可随时插入；
   * 用户提交会刷新提交格式，使挂起的重启在接力时因漂移消失而自动作废。
   */
  private scheduleOrientationRestart(): void {
    if (this.orientationRestartPending || this.coordinator.isClosing) {
      return;
    }
    this.orientationRestartPending = true;
    setTimeout((): void => {
      this.orientationRestartPending = false;
      this.resumeOrientationRestart();
    }, 500);
  }

  /**
   * 转屏重启第二步：延时结束后按最新状态接力。仍停在 CONNECTED 且协调器空闲时，
   * 用最新采集格式和缓存条件重新 start；完成后自检漂移，确认等待期又转屏则重新走停止流程。
   */
  private resumeOrientationRestart(): void {
    if (this.coordinator.isClosing) {
      return;
    }
    if (this.currentState.connectionState !== RealtimeConnectionState.CONNECTED ||
      this.connectionManager.currentSessionId.length === 0 ||
      this.coordinator.hasActiveOperation()) {
      // 已被用户操作接管或连接已断开；GENERATING 下仍有漂移时重新走停止流程，其余由用户操作收尾兜底。
      this.restartGenerationIfOrientationDrifted();
      return;
    }
    const operation: Promise<void> = this.coordinator.run(
      RealtimeOperationKind.GENERATION, null,
      async (token: RealtimeOperationToken): Promise<void> => {
        token.setFailureScope(RealtimeTerminationScope.CONNECTION);
        await this.performStartGeneration(undefined, token);
      });
    this.orientationRestartCompletion = operation;
    void operation.catch((error: Object): void => {
      const resolved: XmaxError = XmaxError.from(error);
      if (resolved.code !== XmaxErrorCode.CANCELLED) {
        this.logCleanupFailure("转屏后重启生成失败 (Failed to Restart Generation after Orientation Change)", resolved);
      }
    }).finally((): void => {
      this.orientationRestartCompletion = null;
      this.restartGenerationIfOrientationDrifted();
    });
  }

  /**
   * 转屏重启的重新提交进行中时，用户新条件经 change_condition 并入该任务并跟随其完成：
   * 条件允许更新，尺寸已由重启保证为最新方向，无需打断重启。不在重启提交窗口时返回空值。
   */
  private tryJoinOrientationRestart(input: RealtimeContext | RealtimeMediaStream | undefined,
    context: RealtimeContext | undefined): Promise<void | RealtimeMediaStream> | null {
    const completion: Promise<void> | null = this.orientationRestartCompletion;
    if (completion === null ||
      (input instanceof RealtimeMediaStream && !this.mediaController.owns(input))) {
      return null;
    }
    const taskId: string = this.streamController.currentGenerationTaskId;
    const videoFormat: RealtimeVideoFormat | undefined =
      this.lastSubmittedFormat ?? this.mediaController.currentVideoFormat;
    if (taskId.length === 0 || videoFormat === undefined ||
      this.connectionManager.currentSessionId.length === 0) {
      return null;
    }
    const newContext: RealtimeContext | undefined =
      input instanceof RealtimeMediaStream ? context : input;
    this.generationManager.update(taskId, videoFormat, newContext);
    if (input instanceof RealtimeMediaStream) {
      return completion.then((): RealtimeMediaStream => {
        const remoteStream: RealtimeMediaStream | null = this.connectionManager.currentRemoteStream;
        if (remoteStream === null) {
          throw new XmaxError(XmaxErrorCode.RTC_ERROR, 'Realtime connection has no remote stream');
        }
        return remoteStream;
      });
    }
    return completion;
  }

  /**
   * 已提交生成任务的方向与当前采集方向不一致时为漂移，需要终止并重建任务。
   * 帧格式回调先于轨道格式更新触发，事件入口需显式传入新格式。
   */
  private hasOrientationDrift(format?: RealtimeVideoFormat): boolean {
    if (this.currentState.connectionState !== RealtimeConnectionState.GENERATING) {
      return false;
    }
    const submitted: RealtimeVideoFormat | undefined = this.lastSubmittedFormat;
    const current: RealtimeVideoFormat | undefined = format ?? this.mediaController.currentVideoFormat;
    if (submitted === undefined || current === undefined) {
      return false;
    }
    return (submitted.width > submitted.height) !== (current.width > current.height);
  }

  private handleCameraVideoFormatChange(format: RealtimeVideoFormat): void {
    const current: RealtimeConnectionState = this.currentState.connectionState;
    if (current === RealtimeConnectionState.DISCONNECTING) {
      return;
    }
    const previous: RealtimeVideoFormat | undefined = this.mediaController.currentVideoFormat;
    const orientationChanged: boolean = previous !== undefined &&
      (previous.width > previous.height) !== (format.width > format.height);
    const track = this.mediaController.currentTrack;
    if (orientationChanged && track !== null) {
      updateRealtimeVideoTrackOrientation(track, format.width > format.height, false);
      // 无视图绑定时靠帧尺寸变化发现转屏；change_condition 无法修改尺寸，方向翻转必须终止并重建任务。
      this.restartGenerationIfOrientationDrifted(format);
    } else {
      // 同方向的分辨率变化仍走 change_condition 更新。
      this.generationManager.updateVideoFormat(format);
    }
    this.connectionManager.updateVideoFormat(format);
  }

  /** 取消连接/生成，等待回滚和清理完成，保留本地媒体与预览。 */
  disconnect(reason: RealtimeReason = RealtimeReason.NORMAL): Promise<void> {
    const current: RealtimeState = this.currentState;
    if ((current.connectionState === RealtimeConnectionState.IDLE ||
      current.connectionState === RealtimeConnectionState.READY ||
      current.connectionState === RealtimeConnectionState.PREPARING) &&
      !this.coordinator.hasOperation(RealtimeOperationKind.CONNECTION) &&
      !this.coordinator.hasOperation(RealtimeOperationKind.GENERATION) &&
      !this.coordinator.hasOperation(RealtimeOperationKind.CAMERA_SWITCH)) {
      return Promise.resolve();
    }
    this.renderController.stopRemoteVideoFrameDelivery();
    return this.coordinator.terminate(RealtimeTerminationScope.CONNECTION, reason);
  }

  /** 立即静默媒体，等待进行中的操作结束后释放所有实时资源。 */
  close(): Promise<void> {
    this.renderController.stopRemoteVideoFrameDelivery();
    const wasClosing: boolean = this.coordinator.isClosing;
    const closing: Promise<void> = this.coordinator.terminate(
      RealtimeTerminationScope.ALL);
    if (!wasClosing) {
      try {
        this.mediaController.setLocalAudioPreviewEnabled(false);
        this.mediaController.prepareForClose();
      } catch (error) {
        this.logCleanupFailure("静默本地媒体失败 (Failed to Mute Local Media)", error);
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
    // 转屏重启的重新提交进行中时，新条件直接并入该任务，不与内部重启竞争操作权。
    const joined: Promise<void | RealtimeMediaStream> | null = this.tryJoinOrientationRestart(input, context);
    if (joined !== null) {
      return joined;
    }
    let measurement: RealtimeTimingRun | null = null;
    const operation = this.coordinator.run<void | RealtimeMediaStream>(RealtimeOperationKind.GENERATION, null,
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
    }).finally((): void => {
      // 首次 start 确认等待期转屏时操作占用中无法立即重启；收尾后自检方向漂移。
      this.restartGenerationIfOrientationDrifted();
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
      token.setFailureScope(null);
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
    if (sessionId.length === 0 || videoFormat === undefined ||
      (current.connectionState !== RealtimeConnectionState.CONNECTED &&
      current.connectionState !== RealtimeConnectionState.GENERATING)) {
      throw new XmaxError(XmaxErrorCode.RTC_ERROR,
        'Realtime connection is not open');
    }
    if (current.connectionState === RealtimeConnectionState.GENERATING && current.taskId !== undefined) {
      this.generationManager.update(current.taskId, videoFormat, context);
      token.ensureCurrent();
      return;
    }
    this.generationManager.validateContext(context);
    token.setFailureScope(RealtimeTerminationScope.CONNECTION);
    this.mediaController.setLocalAudioPreviewEnabled(false);
    // 记录本次提交方向，用于发现确认等待期的转屏漂移；update 分支不改尺寸无需记录。
    this.lastSubmittedFormat = videoFormat;
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
    this.renderController.stopRemoteVideoFrameDelivery();
    try {
      this.mediaController.stopMicrophoneCapture();
    } catch (error) {
      this.logCleanupFailure('停止麦克风采集失败 (Failed to Stop Microphone Capture)', error);
    }
    try {
      this.generationManager.reset(taskId);
    } catch (error) {
      this.logCleanupFailure("停止实时生成失败 (Failed to Stop Realtime Generation)", error);
    }
    let sessionId: string | undefined = this.connectionManager.currentSessionId || undefined;
    try {
      sessionId = (await this.connectionManager.disconnect()) ?? sessionId;
    } catch (error) {
      this.logCleanupFailure("断开实时连接失败 (Failed to Disconnect Realtime Session)", error);
    }
    if (scope === RealtimeTerminationScope.ALL) {
      this.mediaController.setCameraPreviewReadyHandler(null);
      const track = this.mediaController.currentTrack;
      if (track !== null) {
        setRealtimeVideoTrackOrientationHandler(track);
      }
      try {
        await this.mediaController.stopLocalStream();
      } catch (error) {
        this.logCleanupFailure("关闭本地媒体失败 (Failed to Close Local Media)", error);
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
    this.renderController.stopRemoteVideoFrameDelivery();
    return this.coordinator.terminateWithError(error, RealtimeTerminationScope.CONNECTION);
  }

  private logCleanupFailure(title: string, error: Object): void {
    XmaxLogger.error(`${title}${XmaxLogger.localized("\n└─ 原因：", "\n└─ Reason: ")}${XmaxError.from(error).message}`, 'Realtime');
  }

  private handleRuntimeError(error: XmaxError, scope: RealtimeTerminationScope): void {
    this.renderController.stopRemoteVideoFrameDelivery();
    this.renderController.failRemoteFrameWait(error);
    void this.coordinator.terminateWithError(error, scope)
      .catch((failure: Object): void => this.logCleanupFailure("实时错误清理失败 (Realtime Error Cleanup Failed)", failure));
  }

  private reportError(error: Object): XmaxError {
    return this.errorManager.handle(XmaxError.from(error));
  }
}
