//
//  XmaxRealtimeManager.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { UplinkVideoStatisticsListener, DownlinkVideoStatisticsListener } from '../../foundation/rtc/VideoStatistics';
import { ImageSize } from '../../service/media/ImageSize';
import { QualityConfiguration, QualityChange } from '../../stream/quality/QualityConfiguration';
import { QualityVideoFormat } from '../../stream/quality/QualityVideoFormat';
import { QualityPreferences } from '../../stream/quality/QualityPreferences';
import { RealtimeNetworkQuality } from '../../service/realtime/RealtimeNetworkQuality';
import { RealtimeVideoTrack, setRealtimeVideoTrackOrientationHandler, updateRealtimeVideoTrackOrientation } from '../../service/realtime/RealtimeVideoTrack';
import {
  LocalVideoPlaybackState,
  LocalVideoPlaybackStateListener
} from '../../service/realtime/LocalVideoPlaybackState';
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

  /** 公开业务配置 */
  readonly options: RealtimeConfiguration;

  /** 平台与业务组件 */
  private readonly rtcManager: RtcManaging;

  /** 错误管理组件 */
  private readonly errorManager: XmaxRealtimeErrorManager;

  /** 渲染层组件 */
  private readonly renderController: RenderControlling;

  /** 业务层组件 */
  private readonly streamController: StreamControlling;
  private readonly mediaController: MediaControlling;

  /** 实时管理组件 */
  private readonly connectionManager: XmaxRealtimeConnectionManager;
  private readonly generationManager: XmaxRealtimeGenerationManager;

  /** 生成计时与内部配置操作 */
  private readonly timing: RealtimeTiming = new RealtimeTiming();

  /** 方向重建与调档调度状态 */
  /** 转屏重启的采集稳定等待定时器挂起标志，避免重复调度。 */
  private orientationRestartPending: boolean = false;
  private qualityPending: boolean = false;

  /** 转屏重启重新提交的操作句柄；非空时用户新条件并入该任务而不是新建操作。 */
  private orientationRestartCompletion: Promise<void> | null = null;

  /** 最近提交的生成格式 */
  /** 当前生成任务提交时使用的视频格式，用于发现确认等待期的方向漂移。 */
  private lastSubmittedFormat: RealtimeVideoFormat | undefined = undefined;

  /** 生命周期操作协调 */
  private readonly coordinator: RealtimeCoordinator;

  /** 本地播放状态通知 */
  private localVideoPlaybackStateListener: LocalVideoPlaybackStateListener | null = null;

  /**
   * 创建实时生成业务 Manager 并完成内部依赖装配。
   *
   * @param context 访问 RTC、权限和渲染能力所需的页面上下文。
   * @param options 实时生成模型等业务配置。
   * @param apiService 创建和关闭实时会话使用的网络服务。
   * @returns 新建的 XmaxRealtimeManager 实例。
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
      this.timing,
      new QualityPreferences(context)
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
      },
      (): void => {
        if (this.coordinator.isClosing || this.localVideoPlaybackState !== LocalVideoPlaybackState.ENDED) {
          return;
        }
        // 本地播放结束不改变生成会话，远端继续渲染在途结果。
        this.notifyLocalVideoPlaybackState(LocalVideoPlaybackState.ENDED);
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
      this.streamController,
      new MediaService(options.model)
    );
    this.coordinator = new RealtimeCoordinator(this.errorManager,
      (scope: RealtimeTerminationScope, taskId: string): Promise<string | undefined> =>
        this.cleanup(scope, taskId),
      (): boolean => this.mediaController.currentTrack !== null);
  }

  /**
   * 读取实时业务最近一次已提交的状态。
   *
   * @returns 当前实时业务状态。
   */
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
   * 读取当前本地视频的播放状态。
   *
   * @returns 本地视频播放状态；当前输入不是视频时返回 undefined。
   */
  get localVideoPlaybackState(): LocalVideoPlaybackState | undefined {
    return this.mediaController.localVideoPlaybackState;
  }

  /**
   * 设置本地视频文件播放状态监听器；设置后立即回调当前有效状态。
   *
   * @param listener 接收事件的监听器；可空接口传入 null 时清除监听器。
   * @returns 无返回值。
   */
  setLocalVideoPlaybackStateListener(listener: LocalVideoPlaybackStateListener | null): void {
    this.localVideoPlaybackStateListener = listener;
    const state: LocalVideoPlaybackState | undefined = this.localVideoPlaybackState;
    if (state !== undefined) {
      this.notifyLocalVideoPlaybackState(state);
    }
  }


  /**
   * 异步交付当前生成流的 RTC 后处理帧；null 取消监听，未监听时不复制像素。
   * 缓冲区可在回调后持有；按接收顺序逐帧交付，不合并待交付帧。
   * 回调运行在 ArkTS 事件循环中，耗时处理应移交 Worker。
   * 断开后停止交付，监听器配置保留以供后续生成使用。
   *
   * @param listener 接收事件的监听器；可空接口传入 null 时清除监听器。
   * @returns 无返回值。
   */
  setRemoteVideoFrameListener(listener: RealtimeVideoFrameListener | null): void {
    try {
      this.renderController.setRemoteVideoFrameListener(listener);
    } catch (error) {
      throw this.reportError(XmaxError.from(error));
    }
  }

  /**
   * 设置上行视频统计监听器；传入 null 清除，停止发布或断开时以 undefined 清空统计。
   *
   * @param listener 异步接收上行统计或 undefined 清空通知的监听器；null 表示移除。
   * @returns 无返回值。
   */
  setUplinkVideoStatisticsListener(listener: UplinkVideoStatisticsListener | null): void {
    this.streamController.setUplinkVideoStatisticsListener(listener);
  }

  /**
   * 设置当前生成流的下行视频统计监听器；传入 null 清除，流清理时以 undefined 清空统计。
   *
   * @param listener 异步接收当前生成流下行统计或 undefined 清空通知的监听器；null 表示移除。
   * @returns 无返回值。
   */
  setDownlinkVideoStatisticsListener(listener: DownlinkVideoStatisticsListener | null): void {
    this.streamController.setDownlinkVideoStatisticsListener(listener);
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
   * 读取本地视频音频的播放音量。
   *
   * @returns 0～1 的本地播放音量，0 为静音，1 为原始音量。
   */
  get localAudioVolume(): number {
    return this.mediaController.localAudioVolume;
  }

  /**
   * 设置本地视频文件的预览音量，不影响上传的音频和生成期间的自动静音。
   * 可在创建本地流前设置，停止或替换视频后保留。
   *
   * @param volume 0～1 的有限数值；0 为静音，1 为原始音量，默认 0.45。
   * @returns 操作完成时兑现的 Promise。
   */
  async setLocalAudioVolume(volume: number): Promise<void> {
    try {
      this.validateAudioVolume(volume);
      await this.mediaController.setLocalAudioVolume(volume);
    } catch (error) {
      throw this.reportError(XmaxError.from(error));
    }
  }

  /**
   * 读取生成结果流的播放音量。
   *
   * @returns 0～1 的音量比例，0 为静音，1 为原始音量。
   */
  get remoteAudioVolume(): number {
    return this.streamController.remoteAudioVolume;
  }

  /**
   * 设置远端生成结果的播放音量，后续订阅和重连沿用该值。
   * 新建相机/图片流成功后重置为 0，新建视频流成功后重置为 1；自定义音量请在创建流后设置。
   *
   * @param volume 0～1 的有限数值；0 为静音，1 为原始音量；尚未创建本地流时为 1。
   * @returns 操作完成时兑现的 Promise。
   */
  async setRemoteAudioVolume(volume: number): Promise<void> {
    try {
      this.validateAudioVolume(volume);
      this.streamController.setRemoteAudioVolume(volume);
    } catch (error) {
      throw this.reportError(XmaxError.from(error));
    }
  }

  /**
   * 验证音量为 0～1 范围内的有限数值；非法时抛出配置错误。
   *
   * @param volume 音量比例，范围 0～1，0 为静音，1 为原始音量。
   * @returns 无返回值。
   */
  private validateAudioVolume(volume: number): void {
    if (!Number.isFinite(volume) || volume < 0 || volume > 1) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Audio volume must be between 0 and 1'
      );
    }
  }


  /**
   * 创建并启动本地相机流。
   *
   * @param videoFormat 本地视频格式；省略时使用当前模型默认相机规格。
   * @param position 初始相机位置；未传入时使用前置相机。
   * @param useMicrophone 是否启用麦克风，默认 false；创建时申请权限，连接时开始采集，断开时停止。
   * @param observeDisplayChange 是否监听屏幕变化，默认 true；false 时转屏不切换采集比例与方向，也不会因转屏重启生成。
   * @returns 异步返回可用于后续连接、生成或显示的媒体流的 Promise。
   */
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

  /**
   * 停止本地相机流并释放预览资源。
   *
   * @returns 操作完成时兑现的 Promise。
   */
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

  /**
   * 切换摄像头，生成中切换时保留连接并恢复当前生成条件。
   *
   * @returns 异步返回可用于后续连接、生成或显示的媒体流的 Promise。
   */
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

  /**
   * 从本地视频文件创建并启动媒体流，使用当前模型的输入规则。
   *
   * @param filePath 本地视频文件路径。
   * @param videoFormat 期望的视频输出格式；未传入时按文件显示尺寸计算模型输入尺寸，并使用模型默认帧率；显式指定时保留帧率。
   * @param loop 是否循环播放，默认 true；false 时自然结束停止音视频推帧并通知 ENDED，不自动停止生成或断开会话。
   * @returns 异步返回可用于后续连接、生成或显示的媒体流的 Promise。
   */
  async createLocalVideoStream(filePath: string, videoFormat?: RealtimeVideoFormat,
    loop: boolean = true): Promise<RealtimeMediaStream> {
    return this.coordinator.run(RealtimeOperationKind.MEDIA, null,
      async (token: RealtimeOperationToken): Promise<RealtimeMediaStream> => {
        this.ensureLocalMediaCanChange();
        if (this.mediaController.currentTrack !== null) {
          throw new XmaxError(XmaxErrorCode.INVALID_CONFIGURATION, 'Stop the current local stream before creating another one');
        }
        this.mediaController.setCameraPreviewReadyHandler(null);
        this.coordinator.commit(new RealtimeState(RealtimeConnectionState.PREPARING), token);
        const stream = await this.mediaController.createLocalVideoStream(filePath, videoFormat, loop);
        token.ensureCurrent();
        token.setFailureScope(RealtimeTerminationScope.ALL);
        this.notifyLocalVideoPlaybackState(this.localVideoPlaybackState ?? LocalVideoPlaybackState.PLAYING);
        this.observeLocalOrientation(stream);
        this.streamController.setRemoteAudioVolume(1);
        this.coordinator.commit(new RealtimeState(RealtimeConnectionState.READY), token);
        return stream;
      });
  }

  /**
   * 停止本地视频流并释放预览资源。
   *
   * @returns 操作完成时兑现的 Promise。
   */
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

  /**
   * 暂停本地视频文件，保持 RTC 发送冻结帧和静音音频。
   *
   * @returns 操作完成时兑现的 Promise。
   */
  pauseLocalVideoStream(): Promise<void> {
    return this.coordinator.run(RealtimeOperationKind.PLAYBACK, null,
      async (token: RealtimeOperationToken): Promise<void> => {
        this.ensureLocalVideoPlaybackCanChange();
        await this.mediaController.pauseLocalVideoStream();
        token.ensureCurrent();
        this.notifyLocalVideoPlaybackState(LocalVideoPlaybackState.PAUSE);
        token.ensureCurrent();
        await this.renderController.freezeRemoteVideo();
        token.ensureCurrent();
      });
  }

  /**
   * 从暂停位置恢复本地视频文件。
   *
   * @returns 操作完成时兑现的 Promise。
   */
  resumeLocalVideoStream(): Promise<void> {
    return this.coordinator.run(RealtimeOperationKind.PLAYBACK, null,
      async (token: RealtimeOperationToken): Promise<void> => {
        this.ensureLocalVideoPlaybackCanChange();
        this.mediaController.resumeLocalVideoStream();
        token.ensureCurrent();
        await this.renderController.resumeRemoteVideo();
        token.ensureCurrent();
        if (this.localVideoPlaybackState === LocalVideoPlaybackState.PLAYING) {
          this.notifyLocalVideoPlaybackState(LocalVideoPlaybackState.PLAYING);
        }
      });
  }

  /**
   * 在播放和暂停之间切换。
   *
   * @returns 操作完成时兑现的 Promise。
   */
  toggleLocalVideoStreamPlayback(): Promise<void> {
    return this.localVideoPlaybackState === LocalVideoPlaybackState.PAUSE ?
      this.resumeLocalVideoStream() : this.pauseLocalVideoStream();
  }

  /**
   * 从图片输入创建持续输出帧的媒体流。
   *
   * @param source 本地文件路径、图片编码数据或平台 PixelMap。
   * @param videoFormat 期望的视频输出格式；未传入时按图片尺寸计算模型输入尺寸，并使用模型默认帧率；显式指定时保留帧率。
   * @returns 异步返回可用于后续连接、生成或显示的媒体流的 Promise。
   */
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

  /**
   * 停止本地图片流并释放预览资源。
   *
   * @returns 操作完成时兑现的 Promise。
   */
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

  /**
   * 使用当前 Manager 创建的本地流建立实时连接。
   *
   * @param localStream 当前 Manager 创建的本地媒体流。
   * @returns 异步返回可用于后续连接、生成或显示的媒体流的 Promise。
   */
  connect(localStream: RealtimeMediaStream): Promise<RealtimeMediaStream> {
    return this.coordinator.run(RealtimeOperationKind.CONNECTION, null,
      (token: RealtimeOperationToken): Promise<RealtimeMediaStream> => this.performConnect(localStream, token));
  }

  /**
   * 配置媒体传输与连接，并在有效操作中提交已连接状态。
   *
   * @param localStream 已创建的本地媒体流。
   * @param token 用于校验操作所有权和处理取消的令牌。
   * @returns 连接完成后可用于生成和展示的远端媒体流。
   */
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
    const quality: QualityConfiguration = this.streamController.prepareQuality(videoFormat, this.options.model.name);
    this.streamController.setVideoEncoderConfig(quality.uplink);
    token.ensureCurrent();
    this.mediaController.startMicrophoneCapture();
    token.ensureCurrent();
    const remoteStream: RealtimeMediaStream = await this.connectionManager.connect(
      this.options.model.name, videoFormat, this.mediaController.hasAudio,
      (): boolean => token.isCurrent,
      (sessionId: string, error: XmaxError): Promise<void> => this.handleHeartbeatFailure(sessionId, error),
      this.resolveQualityTarget(quality));
    token.ensureCurrent();
    const sessionId: string = this.connectionManager.currentSessionId;
    if (sessionId.length === 0) {
      throw RealtimeOperationToken.cancelledError();
    }
    this.coordinator.commit(new RealtimeState(RealtimeConnectionState.CONNECTED, sessionId), token);
    return remoteStream;
  }

  /**
   * 为当前本地轨道注册方向变化处理，触发必要的生成重建。
   *
   * @param stream 需要绑定或处理的媒体流。
   * @returns 无返回值。
   */
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

  /**
   * 转屏先同步 Native 方向；相机尺寸翻转后经帧格式变化入口重启生成，其他来源不受影响。
   *
   * @returns 无返回值。
   */
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
   *
   * @param format 需要使用的视频格式。
   * @returns 无返回值。
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
   *
   * @returns 无返回值。
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
   *
   * @returns 无返回值。
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
   *
   * @param input 本地媒体流或生成上下文。
   * @param context 生成提示词、参考图和人脸检测配置。
   * @param faceRestoration 是否启用人脸修复。
   * @returns 可合并时返回正在执行的重建 Promise，否则返回 null；携带本地流的调用完成后返回远端媒体流。
   */
  private tryJoinOrientationRestart(input: RealtimeContext | RealtimeMediaStream | undefined,
    context: RealtimeContext | undefined, faceRestoration: boolean): Promise<void | RealtimeMediaStream> | null {
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
    this.generationManager.update(taskId, videoFormat, newContext, faceRestoration);
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
   *
   * @param format 需要使用的视频格式。
   * @returns 当前采集格式与已提交生成格式的横竖方向不一致时返回 true。
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

  /**
   * 将摄像头格式变化同步到连接与生成配置。
   *
   * @param format 需要使用的视频格式。
   * @returns 无返回值。
   */
  private handleCameraVideoFormatChange(format: RealtimeVideoFormat): void {
    const current: RealtimeConnectionState = this.currentState.connectionState;
    if (current === RealtimeConnectionState.DISCONNECTING) {
      return;
    }
    const previous: RealtimeVideoFormat | undefined = this.mediaController.currentVideoFormat;
    const orientationChanged: boolean = previous !== undefined &&
      (previous.width > previous.height) !== (format.width > format.height);
    const quality: QualityConfiguration | undefined = this.streamController.qualityConfiguration;
    if (quality !== undefined && !QualityVideoFormat.same(quality.baseline, format)) {
      const rebased: QualityConfiguration | undefined = this.streamController.rebaseQuality(format);
      if (rebased !== undefined) {
        this.streamController.setVideoEncoderConfig(rebased.uplink);
        const taskId: string | undefined = this.currentState.taskId;
        if (!orientationChanged && current === RealtimeConnectionState.GENERATING && taskId !== undefined) {
          try {
            const target: ImageSize = this.resolveQualityTarget(rebased);
            this.streamController.changeTargetSize(taskId, target);
            this.connectionManager.updateTargetSize(target, format);
          } catch (error) {
            XmaxLogger.warn('Failed to update return size after media change: ' + String(error), 'Quality');
          }
        }
      }
    }
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

  /**
   * 取消连接/生成，等待回滚和清理完成，保留本地媒体与预览。
   *
   * @param reason 本次断开的原因；省略时为 RealtimeReason.NORMAL。
   * @returns 操作完成时兑现的 Promise。
   */
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

  /**
   * 立即静默媒体，等待进行中的操作结束后释放所有实时资源。
   *
   * @returns 操作完成时兑现的 Promise。
   */
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

  /**
   * 开始生成；生成中再次调用则更新条件。传入本地流时按需建立连接。
   *
   * @param context 生成条件；首次开始生成时必须传入。
   * @param faceRestoration 是否启用原始人脸回贴；每次调用默认 false，生成中可更新。
   * @returns 生成启动或更新完成的 Promise；传入本地媒体流时返回远端媒体流，否则不返回值。
   */
  startGeneration(context?: RealtimeContext, faceRestoration?: boolean): Promise<void>;

  /**
   * 使用当前本地流按需连接并开始生成；已经连接时复用连接，生成中更新条件。
   *
   * @param localStream 当前 Manager 创建并持有的本地媒体流。
   * @param context 首次生成必须提供；同一连接内可省略以复用缓存条件。
   * @param faceRestoration 是否启用原始人脸回贴；每次调用默认 false，生成中可更新。
   * @returns 生成启动或更新完成的 Promise；传入本地媒体流时返回远端媒体流，否则不返回值。
   */
  startGeneration(localStream: RealtimeMediaStream, context?: RealtimeContext,
    faceRestoration?: boolean): Promise<RealtimeMediaStream>;

  /**
   * 启动或更新实时生成；传入本地媒体流时先建立连接。
   *
   * @param input 本地媒体流或生成上下文。
   * @param contextOrFaceRestoration 生成上下文，或仅指定人脸修复开关的布尔值。
   * @param faceRestoration 是否启用人脸修复。
   * @returns 生成启动或更新完成的 Promise；传入本地媒体流时返回远端媒体流，否则不返回值。
   */
  startGeneration(input?: RealtimeContext | RealtimeMediaStream,
    contextOrFaceRestoration?: RealtimeContext | boolean, faceRestoration: boolean = false): Promise<void | RealtimeMediaStream> {
    const context: RealtimeContext | undefined =
      typeof contextOrFaceRestoration === 'boolean' ? undefined : contextOrFaceRestoration;
    const resolvedFaceRestoration: boolean = input instanceof RealtimeMediaStream ? faceRestoration :
      (typeof contextOrFaceRestoration === 'boolean' ? contextOrFaceRestoration : false);
    // 转屏重启的重新提交进行中时，新条件直接并入该任务，不与内部重启竞争操作权。
    const joined: Promise<void | RealtimeMediaStream> | null =
      this.tryJoinOrientationRestart(input, context, resolvedFaceRestoration);
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
            return await this.startGenerationWithStream(input, context, token, resolvedFaceRestoration);
          }
          await this.performStartGeneration(input, token, resolvedFaceRestoration);
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

  /**
   * 连接指定本地媒体流后启动生成，并等待远端画面可用。
   *
   * @param localStream 已创建的本地媒体流。
   * @param context 生成提示词、参考图和人脸检测配置。
   * @param token 用于校验操作所有权和处理取消的令牌。
   * @param faceRestoration 是否启用人脸修复。
   * @returns 可供 SDK 视频视图展示的生成结果媒体流。
   */
  private async startGenerationWithStream(localStream: RealtimeMediaStream, context: RealtimeContext | undefined,
    token: RealtimeOperationToken, faceRestoration: boolean): Promise<RealtimeMediaStream> {
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
    await this.performStartGeneration(context, token, faceRestoration);
    return remoteStream;
  }

  /**
   * 提交生成条件并等待结果流确认和首帧就绪。
   *
   * @param context 生成提示词、参考图和人脸检测配置。
   * @param token 用于校验操作所有权和处理取消的令牌。
   * @param faceRestoration 是否启用人脸修复。
   * @returns 操作完成时兑现的 Promise。
   */
  private async performStartGeneration(context: RealtimeContext | undefined,
    token: RealtimeOperationToken, faceRestoration?: boolean): Promise<void> {
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
      this.generationManager.update(current.taskId, videoFormat, context, faceRestoration);
      token.ensureCurrent();
      return;
    }
    this.generationManager.validateContext(context);
    token.setFailureScope(RealtimeTerminationScope.CONNECTION);
    const previousQuality: QualityConfiguration | undefined = this.streamController.qualityConfiguration;
    const quality: QualityConfiguration | undefined = previousQuality === undefined ? undefined :
      QualityVideoFormat.same(previousQuality.baseline, videoFormat) ? previousQuality : this.streamController.rebaseQuality(videoFormat);
    if (quality !== undefined) {
      this.streamController.setVideoEncoderConfig(quality.uplink);
      this.connectionManager.updateTargetSize(this.resolveQualityTarget(quality), videoFormat);
    }
    token.ensureCurrent();
    this.mediaController.setLocalAudioPreviewEnabled(false);
    // 记录本次提交方向，用于发现确认等待期的转屏漂移；update 分支不改尺寸无需记录。
    this.lastSubmittedFormat = videoFormat;
    try {
      const taskId: string = await this.generationManager.start(videoFormat, context,
        (): void => token.ensureCurrent(),
        (confirmation: Promise<void>): Promise<void> => token.wait(confirmation), faceRestoration,
        this.connectionManager.currentTargetSize);
      token.ensureCurrent();
      await token.wait(this.renderController.waitUntilRemoteFrameReady());
      token.ensureCurrent();
      if (this.localVideoPlaybackState === LocalVideoPlaybackState.PAUSE) {
        await token.wait(this.renderController.freezeRemoteVideo());
        token.ensureCurrent();
      }
      this.streamController.activateRemoteAudio();
      if (this.connectionManager.currentSessionId !== sessionId) {
        throw RealtimeOperationToken.cancelledError();
      }
      this.coordinator.commit(new RealtimeState(RealtimeConnectionState.GENERATING, sessionId, taskId), token);
      if (quality !== undefined) {
        this.streamController.completeQuality(false, quality.uplinkLevel, true);
        this.streamController.completeQuality(true, quality.downlinkLevel, true);
      }
      this.streamController.setAdaptiveQualityListener((sample: RealtimeNetworkQuality, sampledAt: number): void => {
        this.scheduleAdaptiveQuality(sample, sampledAt, taskId);
      });
      this.timing.finish(taskId);
    } catch (error) {
      this.restoreLocalAudioPreview();
      throw XmaxError.from(error);
    }
  }

  /**
   * 按已处理的媒体比例和下行档位上限计算结果流目标尺寸。
   *
   * @param configuration 当前上下行档位与固定媒体基准。
   * @returns 计算得到的媒体宽高。
   */
  private resolveQualityTarget(configuration: QualityConfiguration): ImageSize {
    const baseline: RealtimeVideoFormat = configuration.baseline;
    return new MediaService(this.options.model).resolveTargetSize(new ImageSize(baseline.width, baseline.height),
      QualityVideoFormat.resolveDownlinkMaximumSize(baseline, configuration.downlinkLevel));
  }

  /**
   * 在生成任务仍有效且无用户操作占用时安排自动调档。
   *
   * @param sample 上下行网络质量采样。
   * @param sampledAt 网络采样的单调时间，单位秒。
   * @param taskId 当前生成任务标识。
   * @returns 无返回值。
   */
  private scheduleAdaptiveQuality(sample: RealtimeNetworkQuality, sampledAt: number, taskId: string): void {
    if (this.qualityPending) { return; }
    this.qualityPending = true;
    // 用户的同步网络监听先执行；用户发起的操作可使本次后台采样直接跳过。
    void Promise.resolve().then((): void => {
      if (this.currentState.taskId !== taskId) { return; }
      const accepted: boolean = this.coordinator.runAdaptiveConfiguration((token: RealtimeOperationToken): void => {
        if (this.currentState.taskId !== taskId) { return; }
        const change: QualityChange = this.streamController.proposeQuality(sample, sampledAt);
        if (change.uplink !== undefined) { this.applyQualityLevel(change.uplink, false, taskId, token); }
        token.ensureCurrent();
        if (change.downlink !== undefined) { this.applyQualityLevel(change.downlink, true, taskId, token); }
      });
      if (!accepted) { this.streamController.resetQualitySamples(); }
    }).catch((error: Object): void => {
      this.streamController.resetQualitySamples();
      if (this.currentState.taskId === taskId && XmaxError.from(error).code !== XmaxErrorCode.CANCELLED) {
        XmaxLogger.warn('Adaptive quality skipped: ' + String(error), 'Quality');
      }
    }).finally((): void => { this.qualityPending = false; });
  }

  /**
   * 向指定方向提交档位配置，并记录配置提交是否成功。
   *
   * @param level 传输档位，范围 1～5，数值越小质量越高。
   * @param downlink 是否为下行方向；false 表示上行。
   * @param taskId 当前生成任务标识。
   * @param token 用于校验操作所有权和处理取消的令牌。
   * @returns 无返回值。
   */
  private applyQualityLevel(level: number, downlink: boolean, taskId: string, token: RealtimeOperationToken): void {
    const configuration: QualityConfiguration | undefined = this.streamController.qualityConfiguration;
    if (configuration === undefined) { return; }
    try {
      token.ensureCurrent();
      if (this.currentState.taskId !== taskId) { return; }
      if (downlink) {
        const candidate: QualityConfiguration = new QualityConfiguration(configuration.baseline, configuration.uplinkLevel, level);
        const target: ImageSize = this.resolveQualityTarget(candidate);
        const previous: ImageSize | undefined = this.connectionManager.currentTargetSize;
        if (previous === undefined || previous.width !== target.width || previous.height !== target.height) {
          this.streamController.changeTargetSize(taskId, target);
          token.ensureCurrent();
          this.connectionManager.updateTargetSize(target, configuration.baseline);
        }
      } else {
        this.streamController.setVideoEncoderConfig(QualityVideoFormat.resolve(configuration.baseline, level, false));
      }
      token.ensureCurrent();
      this.streamController.completeQuality(downlink, level, true);
      XmaxLogger.debug(`Adaptive quality: ${downlink ? 'downlink' : 'uplink'} L${level}`, 'Quality');
    } catch (error) {
      if (!token.isCurrent) { throw XmaxError.from(error); }
      this.streamController.completeQuality(downlink, level, false);
      XmaxLogger.warn('Adaptive quality failed: ' + String(error), 'Quality');
    }
  }

  /**
   * 验证是否允许替换本地媒体；业务忙碌或已连接时抛出配置错误。
   *
   * @returns 无返回值。
   */
  private ensureLocalMediaCanChange(): void {
    const current: RealtimeState = this.currentState;
    if (this.connectionManager.currentSessionId.length > 0 ||
      current.connectionState === RealtimeConnectionState.CONNECTING ||
      current.connectionState === RealtimeConnectionState.DISCONNECTING) {
      throw new XmaxError(XmaxErrorCode.INVALID_CONFIGURATION,
        'Disconnect realtime before changing the local media stream');
    }
  }

  /**
   * 验证当前是否允许暂停或恢复本地视频；不可用时抛出配置错误。
   *
   * @returns 无返回值。
   */
  private ensureLocalVideoPlaybackCanChange(): void {
    const current: RealtimeConnectionState = this.currentState.connectionState;
    if (this.localVideoPlaybackState === LocalVideoPlaybackState.ENDED) {
      throw new XmaxError(XmaxErrorCode.INVALID_CONFIGURATION,
        'Local video playback has ended; stop and recreate the stream to replay');
    }
    if (this.localVideoPlaybackState === undefined ||
      current === RealtimeConnectionState.PREPARING ||
      current === RealtimeConnectionState.CONNECTING ||
      current === RealtimeConnectionState.DISCONNECTING) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Local video playback cannot change while realtime is transitioning'
      );
    }
  }

  /**
   * 通知本地视频播放状态，并隔离业务监听器异常。
   *
   * @param state 需要通知的业务状态。
   * @returns 无返回值。
   */
  private notifyLocalVideoPlaybackState(state: LocalVideoPlaybackState): void {
    try {
      this.localVideoPlaybackStateListener?.(state);
    } catch (error) {
      XmaxLogger.error(
        `${XmaxLogger.localized("本地视频播放状态监听器执行失败 (Local Video Playback State Listener Failed)\n└─ 原因：", "本地视频播放状态监听器执行失败 (Local Video Playback State Listener Failed)\n└─ Reason: ")}${XmaxError.from(error).message}`,
        'Realtime'
      );
    }
  }

  /**
   * 清理失败只记录日志，继续释放后续资源，保留触发终止的原始错误。
   *
   * @param scope 需要释放资源的清理范围。
   * @param taskId 当前生成任务标识。
   * @returns 资源清理完成的 Promise，携带已关闭会话标识；无会话时为 undefined。
   */
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

  /**
   * 按本地视频播放状态恢复本地音频预览。
   *
   * @returns 无返回值。
   */
  private restoreLocalAudioPreview(): void {
    if (!this.coordinator.isClosing) {
      this.mediaController.setLocalAudioPreviewEnabled(true);
    }
  }

  /**
   * 仅处理当前会话的心跳故障，终止连接并保留本地预览。
   *
   * @param sessionId 服务端实时会话标识。
   * @param error 当前操作失败或终止的原因。
   * @returns 操作完成时兑现的 Promise。
   */
  private handleHeartbeatFailure(sessionId: string, error: XmaxError): Promise<void> {
    if (this.connectionManager.currentSessionId !== sessionId) {
      return Promise.resolve();
    }
    this.renderController.stopRemoteVideoFrameDelivery();
    return this.coordinator.terminateWithError(error, RealtimeTerminationScope.CONNECTION);
  }

  /**
   * 记录资源清理失败的操作名称和原因。
   *
   * @param title 日志所描述的阶段或操作名称。
   * @param error 当前操作失败或终止的原因。
   * @returns 无返回值。
   */
  private logCleanupFailure(title: string, error: Object): void {
    XmaxLogger.error(`${title}${XmaxLogger.localized("\n└─ 原因：", "\n└─ Reason: ")}${XmaxError.from(error).message}`, 'Realtime');
  }

  /**
   * 在指定范围终止故障资源，并由统一错误流程通知接入方。
   *
   * @param error 当前操作失败或终止的原因。
   * @param scope 需要释放资源的清理范围。
   * @returns 无返回值。
   */
  private handleRuntimeError(error: XmaxError, scope: RealtimeTerminationScope): void {
    this.renderController.stopRemoteVideoFrameDelivery();
    this.renderController.failRemoteFrameWait(error);
    void this.coordinator.terminateWithError(error, scope)
      .catch((failure: Object): void => this.logCleanupFailure("实时错误清理失败 (Realtime Error Cleanup Failed)", failure));
  }

  /**
   * 将任意异常转为 SDK 错误并交给统一错误管理器。
   *
   * @param error 当前操作失败或终止的原因。
   * @returns 完成转换和通知去重后的 SDK 错误。
   */
  private reportError(error: Object): XmaxError {
    return this.errorManager.handle(XmaxError.from(error));
  }
}
