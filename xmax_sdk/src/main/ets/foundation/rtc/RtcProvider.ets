import { common } from '@kit.AbilityKit';
import {
  AudioChannel,
  AudioFrameType,
  AudioSampleRate,
  AudioSourceType,
  CapturePreference,
  ExternalAudioFrame,
  LocalStreamStats,
  MirrorType,
  NetworkQualityStats,
  PerformanceAlarmMode,
  PerformanceAlarmReason,
  RemoteStreamKey,
  RemoteStreamStats,
  RoomProfileType,
  RTCEngine,
  RTCRoom,
  RTCRoomConfig,
  SourceWantedData,
  StreamIndex,
  SysStats,
  UserInfo,
  VideoCanvas,
  VideoEncodePreference,
  VideoEncoderConfig,
  VideoFrameData,
  VideoSourceType
} from '@bytertc/volcenginertc';
import { AudioFrame } from '../media/audio/AudioFrame';
import {
  XmaxError,
  XmaxErrorCode
} from '../errors/XmaxError';
import { XmaxLogger } from '../logging/XmaxLogger';
import { CameraPosition } from '../media/camera/CameraPosition';
import { VideoFrame } from '../media/video/VideoFrame';
import { VideoContentMode } from '../media/video/VideoContentMode';
import { RemoteStream } from './RemoteStream';
import { RoomJoinConfiguration } from './RoomJoinConfiguration';
import {
  RtcEngineLease,
  RtcEngineProvider
} from './RtcEngineProvider';
import { RtcProviding } from './RtcProviding';
import { RtcEventListener } from './RtcEventListener';
import { RtcQualityConverter } from './RtcQualityConverter';
import { RtcQualityListener } from './RtcQualityListener';
import { RtcStatsLogger } from './RtcStatsLogger';
import { RtcVideoConverter } from './RtcVideoConverter';
import { VideoEncodingConfiguration } from './VideoEncodingConfiguration';

const JOIN_TIMEOUT_MS: number = 15000;

/** 封装第三方 RTC 引擎、房间、媒体传输和渲染绑定能力。 */
export class RtcProvider implements RtcProviding {

  // 平台资源
  private readonly context: common.UIAbilityContext;

  // RTC 资源
  private readonly remoteStreamKeys: Map<string, RemoteStreamKey> = new Map();
  private engineLease: RtcEngineLease | null = null;
  private room: RTCRoom | null = null;
  private pendingRoom: RTCRoom | null = null;
  private pendingJoinCancellation: (() => void) | null = null;

  // 事件监听
  private listener: RtcEventListener | null = null;
  private qualityListener: RtcQualityListener | null = null;

  // 运行状态
  private localVideoMirrorType: MirrorType = MirrorType.kMirrorTypeNone;
  private activeRoomId: string = '';

  /**
   * 创建 RTC Provider。
   *
   * @param context 创建 RTC Engine 使用的平台上下文。
   */
  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  /**
   * 获取当前租约持有的 RTC Engine。
   *
   * @returns 已初始化的 RTC Engine；尚未初始化时返回空值。
   */
  private get engine(): RTCEngine | null {
    return this.engineLease?.engine ?? null;
  }

  /**
   * 获取独占 RTC Engine 租约并绑定全局事件。
   *
   * @returns RTC Engine 初始化完成后的 Promise。
   */
  async initialize(): Promise<void> {
    if (this.engineLease !== null) {
      return;
    }

    const lease: RtcEngineLease = await RtcEngineProvider.acquire(this.context);
    const engine: RTCEngine = lease.engine;

    engine.on('onSEIMessageReceived', (key: RemoteStreamKey, message: string): void => {
      if (this.engine !== engine || key.room_id !== this.activeRoomId) {
        return;
      }

      const stream = new RemoteStream(key.room_id, key.user_id);
      this.remoteStreamKeys.set(stream.key(), key);
      this.listener?.onSeiMessageReceived(stream, message);
    });
    engine.on('onSysStats', (stats: SysStats): void => {
      if (this.engine !== engine) {
        return;
      }

      RtcStatsLogger.logSystemStats(stats);
    });
    engine.on(
      'onPerformanceAlarms',
      (
        _mode: PerformanceAlarmMode,
        roomId: string,
        reason: PerformanceAlarmReason,
        data: SourceWantedData
      ): void => {
        if (this.engine !== engine || roomId !== this.activeRoomId) {
          return;
        }

        RtcStatsLogger.logPerformanceAlarm(reason, data);
        this.emitPerformanceAlarm(reason, data);
      }
    );

    this.engineLease = lease;
  }

  /**
   * 离开当前房间、解除全局事件并释放 RTC Engine 租约。
   *
   * @returns RTC 资源释放完成后的 Promise。
   */
  async destroy(): Promise<void> {
    const lease: RtcEngineLease | null = this.engineLease;
    this.engineLease = null;
    this.remoteStreamKeys.clear();

    try {
      await this.leaveRoom();
    } finally {
      if (lease !== null) {
        const engine: RTCEngine = lease.engine;
        try {
          engine.off('onSEIMessageReceived');
          engine.off('onSysStats');
          engine.off('onPerformanceAlarms');
        } finally {
          await RtcEngineProvider.release(lease);
        }
      }
    }
  }

  /**
   * 将中性视频编码配置应用到 RTC Engine。
   *
   * @param configuration 视频编码配置。
   * @returns 无返回值。
   */
  configureVideoEncoding(configuration: VideoEncodingConfiguration): void {
    const engine: RTCEngine = this.requireEngine();
    const encoderConfiguration: VideoEncoderConfig = {
      width: configuration.width,
      height: configuration.height,
      frame_rate: configuration.frameRate,
      min_bitrate: configuration.minimumBitrate,
      max_bitrate: configuration.maximumBitrate,
      encoder_preference: VideoEncodePreference.kVideoEncodePreferenceFramerate
    };
    this.checkResult(
      engine.setVideoEncoderConfig(encoderConfiguration),
      'setVideoEncoderConfig'
    );
  }

  /**
   * 切换为 RTC 内部视频源并按指定格式启动摄像头采集。
   *
   * @param width 采集宽度。
   * @param height 采集高度。
   * @param frameRate 采集帧率。
   * @returns 无返回值。
   */
  startVideoCapture(
    width: number,
    height: number,
    frameRate: number
  ): void {
    const engine: RTCEngine = this.requireEngine();
    this.checkResult(
      engine.setVideoSourceType(
        StreamIndex.kStreamIndexMain,
        VideoSourceType.kVideoSourceTypeInternal
      ),
      'setVideoSourceType'
    );

    this.checkResult(
      engine.setVideoCaptureConfig({
        capture_preference: CapturePreference.kManual,
        width: width,
        height: height,
        frame_rate: frameRate
      }),
      'setVideoCaptureConfig'
    );

    this.checkResult(
      engine.startVideoCapture(),
      'startVideoCapture'
    );
  }

  /**
   * 停止 RTC 内部摄像头采集。
   *
   * @returns 无返回值。
   */
  stopVideoCapture(): void {
    const engine: RTCEngine | null = this.engine;
    if (engine !== null) {
      this.checkResult(
        engine.stopVideoCapture(),
        'stopVideoCapture'
      );
    }
  }

  /**
   * 切换内部采集摄像头并同步本地视频镜像配置。
   *
   * @param position 目标摄像头位置。
   * @returns 无返回值。
   */
  switchCamera(position: CameraPosition): void {
    const engine: RTCEngine = this.requireEngine();
    this.checkResult(
      engine.switchCamera(RtcVideoConverter.convertCameraId(position)),
      'switchCamera'
    );

    this.localVideoMirrorType = RtcVideoConverter.convertMirrorType(position);
    this.checkResult(
      engine.setLocalVideoMirrorType(this.localVideoMirrorType),
      'setLocalVideoMirrorType'
    );
  }

  /**
   * 将主视频流切换为外部视频源并关闭 RTC 镜像处理。
   *
   * @returns 无返回值。
   */
  useExternalVideoSource(): void {
    const engine: RTCEngine = this.requireEngine();
    this.checkResult(
      engine.setVideoSourceType(
        StreamIndex.kStreamIndexMain,
        VideoSourceType.kVideoSourceTypeExternal
      ),
      'setVideoSourceType'
    );

    this.localVideoMirrorType = MirrorType.kMirrorTypeNone;
    this.checkResult(
      engine.setLocalVideoMirrorType(this.localVideoMirrorType),
      'setLocalVideoMirrorType'
    );
  }

  /**
   * 将音频输入切换为外部音频源并启动 RTC 音频采集通道。
   *
   * @returns 无返回值。
   */
  startExternalAudioSource(): void {
    const engine: RTCEngine = this.requireEngine();
    this.checkResult(
      engine.setAudioSourceType(
        AudioSourceType.kAudioSourceTypeExternal
      ),
      'setAudioSourceType'
    );

    this.checkResult(
      engine.startAudioCapture(),
      'startAudioCapture'
    );
  }

  /**
   * 停止 RTC 外部音频采集通道。
   *
   * @returns 无返回值。
   */
  stopExternalAudioSource(): void {
    const engine: RTCEngine | null = this.engine;
    if (engine !== null) {
      this.checkResult(
        engine.stopAudioCapture(),
        'stopAudioCapture'
      );
    }
  }

  /**
   * 根据摄像头位置更新本地视频镜像配置。
   *
   * @param position 当前摄像头位置。
   * @returns 无返回值。
   */
  configureLocalVideoMirror(position: CameraPosition): void {
    this.localVideoMirrorType = RtcVideoConverter.convertMirrorType(position);
    if (this.engine !== null) {
      this.checkResult(
        this.engine.setLocalVideoMirrorType(this.localVideoMirrorType),
        'setLocalVideoMirrorType'
      );
    }
  }

  /**
   * 转换并推送一帧外部视频数据，可同时携带 SEI。
   *
   * @param frame 中性视频帧。
   * @param seiData 随视频帧发送的附加数据。
   * @returns 无返回值。
   */
  pushExternalVideoFrame(
    frame: VideoFrame,
    seiData?: Uint8Array
  ): void {
    const rtcFrame: VideoFrameData = RtcVideoConverter.convertFrame(
      frame,
      seiData
    );
    const result: number = this.requireEngine().pushExternalVideoFrame(rtcFrame);
    if (result < 0) {
      XmaxLogger.error(
        `推送外部视频帧失败\n└─ 返回码：${result}`,
        'RTC'
      );

      return;
    }
  }

  /**
   * 将中性 PCM 音频帧转换并推送到 RTC Engine。
   *
   * @param frame 10ms PCM 音频帧。
   * @returns 无返回值。
   */
  pushExternalAudioFrame(frame: AudioFrame): void {
    const externalFrame: ExternalAudioFrame = {
      frame_type: AudioFrameType.kFrameTypePCM16,
      sample_rate: AudioSampleRate.kAudioSampleRate48000,
      channel: AudioChannel.kAudioChannelMono,
      timestamp_ms: frame.timestampUs / 1000,
      data: frame.data
    };

    const result: number = this.requireEngine().pushExternalAudioFrame(
      externalFrame
    );

    if (result < 0) {
      XmaxLogger.error(
        `推送外部音频帧失败\n└─ 返回码：${result}`,
        'RTC'
      );
      return;
    }
  }

  /**
   * 创建 RTC 房间，绑定房间事件并等待加入结果。
   *
   * @param configuration 房间加入配置。
   * @returns 加入房间完成后的 Promise。
   */
  async joinRoom(configuration: RoomJoinConfiguration): Promise<void> {
    const engine: RTCEngine = this.requireEngine();
    if (this.room !== null || this.pendingRoom !== null ||
      this.pendingJoinCancellation !== null) {
      throw new XmaxError(XmaxErrorCode.RTC_ERROR, 'RTC room is already active');
    }

    let roomCreationCancelled: boolean = false;
    const cancelRoomCreation = (): void => {
      roomCreationCancelled = true;
    };
    this.pendingJoinCancellation = cancelRoomCreation;

    let room: RTCRoom;
    try {
      room = await engine.createRTCRoom(configuration.roomId);
    } catch (error) {
      if (this.pendingJoinCancellation === cancelRoomCreation) {
        this.pendingJoinCancellation = null;
      }

      throw XmaxError.from(error);
    }

    if (roomCreationCancelled || this.pendingJoinCancellation !== cancelRoomCreation) {
      await room.destroy();
      throw new XmaxError(XmaxErrorCode.CANCELLED, 'RTC join room was cancelled');
    }

    this.pendingRoom = room;
    this.bindRoomEvents(room);

    const userInfo: UserInfo = { uid: configuration.userId, extra_info: '' };
    const roomConfiguration: RTCRoomConfig = {
      room_profile_type: RoomProfileType.kRoomProfileTypeCommunication,
      is_publish_video: false,
      is_publish_audio: false,
      is_auto_subscribe_video: true,
      is_auto_subscribe_audio: false
    };

    try {
      await this.waitForJoin(room, configuration.token, userInfo, roomConfiguration);
      if (this.pendingRoom !== room) {
        throw new XmaxError(XmaxErrorCode.CANCELLED, 'RTC join room was cancelled');
      }

      this.pendingRoom = null;
      this.pendingJoinCancellation = null;
      this.room = room;
      this.activeRoomId = configuration.roomId;
    } catch (error) {
      if (this.pendingRoom === room) {
        this.pendingRoom = null;
        this.pendingJoinCancellation = null;
        await room.destroy();
      }

      throw XmaxError.from(error);
    }
  }

  /**
   * 取消进行中的加入操作并销毁当前 RTC 房间资源。
   *
   * @returns 离开房间完成后的 Promise。
   */
  async leaveRoom(): Promise<void> {
    const room: RTCRoom | null = this.room;
    const pendingRoom: RTCRoom | null = this.pendingRoom;
    const cancelPendingJoin: (() => void) | null = this.pendingJoinCancellation;

    this.room = null;
    this.pendingRoom = null;
    this.pendingJoinCancellation = null;
    this.activeRoomId = '';
    this.remoteStreamKeys.clear();

    cancelPendingJoin?.();

    if (pendingRoom !== null) {
      await pendingRoom.destroy();
    }

    if (room !== null) {
      room.publishStreamVideo(false);
      room.publishStreamAudio(false);
      room.leaveRoom();
      await room.destroy();
    }
  }

  /**
   * 应用镜像配置并发布本地主视频流。
   *
   * @returns 无返回值。
   */
  publishLocalVideo(): void {
    const room: RTCRoom = this.requireRoom();
    this.checkResult(
      this.requireEngine().setLocalVideoMirrorType(this.localVideoMirrorType),
      'setLocalVideoMirrorType'
    );

    this.checkResult(
      room.publishStreamVideo(true),
      'publishStreamVideo'
    );
  }

  /**
   * 在房间存在时停止发布本地主视频流。
   *
   * @returns 无返回值。
   */
  unpublishLocalVideo(): void {
    if (this.room !== null) {
      this.room.publishStreamVideo(false);
    }
  }

  /**
   * 发布本地音频流。
   *
   * @returns 无返回值。
   */
  publishLocalAudio(): void {
    this.checkResult(
      this.requireRoom().publishStreamAudio(true),
      'publishStreamAudio'
    );
  }

  /**
   * 在房间存在时停止发布本地音频流。
   *
   * @returns 无返回值。
   */
  unpublishLocalAudio(): void {
    if (this.room !== null) {
      this.room.publishStreamAudio(false);
    }
  }

  /**
   * 更新指定远端用户的视频订阅状态。
   *
   * @param userId 远端用户标识。
   * @param subscribe 是否订阅视频流。
   * @returns 无返回值。
   */
  subscribeRemoteVideo(
    userId: string,
    subscribe: boolean
  ): void {
    this.checkResult(
      this.requireRoom().subscribeStreamVideo(userId, subscribe),
      'subscribeStreamVideo'
    );
  }

  /**
   * 创建 RTC 渲染画布并绑定本地主视频流。
   *
   * @param viewId 渲染视图标识。
   * @param contentMode 视频内容显示模式。
   * @returns 无返回值。
   */
  bindLocalVideo(
    viewId: string,
    contentMode: VideoContentMode
  ): void {
    const canvas: VideoCanvas = RtcVideoConverter.createCanvas(
      viewId,
      contentMode
    );
    this.checkResult(
      this.requireEngine().setLocalVideoCanvas(StreamIndex.kStreamIndexMain, canvas),
      'setLocalVideoCanvas'
    );

    this.checkResult(
      this.requireEngine().setLocalVideoMirrorType(this.localVideoMirrorType),
      'setLocalVideoMirrorType'
    );
  }

  /**
   * 使用隐藏画布解除本地主视频流的渲染绑定。
   *
   * @returns 无返回值。
   */
  unbindLocalVideo(): void {
    if (this.engine !== null) {
      this.engine.setLocalVideoCanvas(
        StreamIndex.kStreamIndexMain,
        RtcVideoConverter.createHiddenCanvas()
      );
    }
  }

  /**
   * 将中性远端流映射到 RTC 流键并绑定渲染视图。
   *
   * @param stream 远端流信息。
   * @param viewId 渲染视图标识。
   * @param contentMode 视频内容显示模式。
   * @returns 无返回值。
   */
  bindRemoteVideo(
    stream: RemoteStream,
    viewId: string,
    contentMode: VideoContentMode
  ): void {
    const key: RemoteStreamKey | undefined = this.remoteStreamKeys.get(stream.key());
    if (key === undefined) {
      throw new XmaxError(XmaxErrorCode.RTC_ERROR, 'Remote stream is unavailable');
    }

    this.checkResult(
      this.requireEngine().setRemoteVideoCanvas(
        key,
        RtcVideoConverter.createCanvas(viewId, contentMode)
      ),
      'setRemoteVideoCanvas'
    );
  }

  /**
   * 使用隐藏画布解除指定远端视频流的渲染绑定。
   *
   * @param stream 远端流信息。
   * @returns 无返回值。
   */
  unbindRemoteVideo(stream: RemoteStream): void {
    const key: RemoteStreamKey | undefined = this.remoteStreamKeys.get(stream.key());
    if (this.engine !== null && key !== undefined) {
      this.engine.setRemoteVideoCanvas(
        key,
        RtcVideoConverter.createHiddenCanvas()
      );
    }
  }

  /**
   * 获取 RTC Surface 使用的渲染库名称。
   *
   * @returns RTC 渲染库名称。
   */
  renderLibraryName(): string {
    return 'volcenginertc_sdk';
  }

  /**
   * 向当前 RTC 房间发送文本消息。
   *
   * @param message 消息内容。
   * @returns 无返回值。
   */
  sendRoomMessage(message: string): void {
    this.checkResult(
      this.requireRoom().sendRoomMessage(message),
      'sendRoomMessage'
    );
  }

  /**
   * 设置 RTC 媒体和 SEI 事件监听器。
   *
   * @param listener RTC 事件监听器；传入空值时清除监听器。
   * @returns 无返回值。
   */
  setEventListener(listener: RtcEventListener | null): void {
    this.listener = listener;
  }

  /**
   * 设置 RTC 网络质量和性能告警监听器。
   *
   * @param listener RTC 质量事件监听器；传入空值时清除监听器。
   * @returns 无返回值。
   */
  setQualityListener(listener: RtcQualityListener | null): void {
    this.qualityListener = listener;
  }

  /**
   * 绑定指定 RTC 房间的媒体发布、流统计和网络质量事件。
   *
   * @param room 需要绑定事件的 RTC 房间。
   * @returns 无返回值。
   */
  private bindRoomEvents(room: RTCRoom): void {
    room.on(
      'onUserPublishStreamVideo',
      (_roomId: string, userId: string, published: boolean): void => {
        if (this.room !== room) {
          return;
        }

        this.listener?.onRemoteVideoPublished(userId, published);
      }
    );

    room.on('onLocalStreamStats', (stats: LocalStreamStats): void => {
      if (this.room !== room) {
        return;
      }

      RtcStatsLogger.logLocalStreamStats(stats);
    });

    room.on('onRemoteStreamStats', (stats: RemoteStreamStats): void => {
      if (this.room !== room) {
        return;
      }

      RtcStatsLogger.logRemoteStreamStats(stats);
    });

    room.on(
      'onNetworkQuality',
      (
        localQuality: NetworkQualityStats,
        remoteQualities: NetworkQualityStats[]
      ): void => {
        if (this.room !== room) {
          return;
        }

        RtcStatsLogger.logNetworkQuality(localQuality, remoteQualities);
        this.emitNetworkQuality(localQuality, remoteQualities);
      }
    );
  }

  /**
   * 将 RTC 网络质量统计转换后通知质量监听器。
   *
   * @param localQuality 本地上下行网络质量统计。
   * @param remoteQualities 远端用户网络质量统计。
   * @returns 无返回值。
   */
  private emitNetworkQuality(
    localQuality: NetworkQualityStats,
    remoteQualities: NetworkQualityStats[]
  ): void {
    const listener: RtcQualityListener | null = this.qualityListener;
    if (listener === null) {
      return;
    }

    listener.onNetworkQuality(
      RtcQualityConverter.convertLevel(localQuality.tx_quality),
      RtcQualityConverter.resolveDownlinkLevel(remoteQualities)
    );
  }

  /**
   * 将 RTC 性能告警转换后通知质量监听器。
   *
   * @param reason RTC 性能告警原因。
   * @param data RTC 建议的媒体配置。
   * @returns 无返回值。
   */
  private emitPerformanceAlarm(
    reason: PerformanceAlarmReason,
    data: SourceWantedData
  ): void {
    const listener: RtcQualityListener | null = this.qualityListener;
    if (listener === null) {
      return;
    }

    const limited: boolean | undefined =
      RtcQualityConverter.resolvePerformanceLimited(reason);
    if (limited === undefined) {
      return;
    }

    listener.onPerformanceAlarm(
      limited,
      data.width,
      data.heigth,
      data.frame_rate
    );
  }

  /**
   * 等待 RTC 房间加入事件，并提供取消和超时保护。
   *
   * @param room 待加入的 RTC 房间。
   * @param token 房间访问令牌。
   * @param userInfo 本地用户信息。
   * @param configuration 房间配置。
   * @returns 加入房间成功后的 Promise。
   */
  private waitForJoin(
    room: RTCRoom,
    token: string,
    userInfo: UserInfo,
    configuration: RTCRoomConfig
  ): Promise<void> {
    return new Promise((resolve: () => void, reject: (reason: XmaxError) => void) => {
      let settled: boolean = false;
      let timerId: number = -1;
      this.pendingJoinCancellation = (): void => {
        if (settled) {
          return;
        }

        settled = true;
        clearTimeout(timerId);
        reject(new XmaxError(XmaxErrorCode.CANCELLED, 'RTC join room was cancelled'));
      };
      timerId = setTimeout((): void => {
        if (!settled) {
          settled = true;
          reject(new XmaxError(XmaxErrorCode.TIMEOUT, 'RTC join room timed out'));
        }
      }, JOIN_TIMEOUT_MS);
      room.on(
        'onRoomStateChanged',
        (_roomId: string, _userId: string, state: number, _extra: string): void => {
          if (settled) {
            return;
          }
          settled = true;
          clearTimeout(timerId);
          if (state === 0) {
            resolve();
          } else {
            reject(new XmaxError(
              XmaxErrorCode.RTC_ERROR,
              `RTC join room failed: ${state}`
            ));
          }
        }
      );
      const result: number = room.joinRoom(token, userInfo, configuration);
      if (result < 0 && !settled) {
        settled = true;
        clearTimeout(timerId);
        reject(new XmaxError(XmaxErrorCode.RTC_ERROR, `joinRoom failed: ${result}`));
      }
    });
  }

  /**
   * 获取已初始化的 RTC Engine。
   *
   * @returns 当前 RTC Engine。
   */
  private requireEngine(): RTCEngine {
    if (this.engine === null) {
      throw new XmaxError(XmaxErrorCode.RTC_ERROR, 'RTC engine is not initialized');
    }
    return this.engine;
  }

  /**
   * 获取已加入的 RTC 房间。
   *
   * @returns 当前 RTC 房间。
   */
  private requireRoom(): RTCRoom {
    if (this.room === null) {
      throw new XmaxError(XmaxErrorCode.RTC_ERROR, 'RTC room is not joined');
    }
    return this.room;
  }

  /**
   * 校验 RTC 同步调用返回码。
   *
   * @param result RTC 调用返回码。
   * @param operation RTC 操作名称。
   * @returns 无返回值。
   */
  private checkResult(
    result: number,
    operation: string
  ): void {
    if (result < 0) {
      throw new XmaxError(XmaxErrorCode.RTC_ERROR, `${operation} failed: ${result}`);
    }
  }

}
