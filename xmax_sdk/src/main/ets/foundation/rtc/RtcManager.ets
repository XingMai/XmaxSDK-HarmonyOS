//
//  RtcManager.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import {
  AudioChannel,
  AudioFrameType,
  AudioSampleRate,
  AudioSourceType,
  ExternalAudioFrame,
  IVideoFrame,
  LocalStreamStats,
  MirrorType,
  NetworkQualityStats,
  PerformanceAlarmMode,
  PerformanceAlarmReason,
  RemoteStreamKey,
  RemoteStreamStats,
  RemoteVideoSinkPosition,
  RoomProfileType,
  RTCEngine,
  RTCRoom,
  RTCRoomConfig,
  SourceWantedData,
  StreamIndex,
  UserInfo,
  VideoCanvas,
  VideoApplyRotation,
  VideoEncoderConfig,
  VideoFrameData,
  VideoFrameInfo,
  VideoPixelFormat,
  VideoSinkMirrorType,
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
  RtcEngineManager
} from './RtcEngineManager';
import { RtcManaging, RtcRemoteVideoFrameListener, RtcRemoteVideoRenderedListener } from './RtcManaging';
import { RtcEventListener } from './RtcEventListener';
import { RtcQualityConverter } from './RtcQualityConverter';
import { RtcQualityListener } from './RtcQualityListener';
import { RtcStatsLogger } from './RtcStatsLogger';
import { VolcRtcStatsLogger } from './VolcRtcStatsLogger';
import { UplinkVideoStatistics, DownlinkVideoStatistics } from './VideoStatistics';
import { RtcVideoConverter } from './RtcVideoConverter';
import { VideoEncodingConfiguration } from './VideoEncodingConfiguration';

const JOIN_TIMEOUT_MS: number = 15000;
const SNAPSHOT_TIMEOUT_MS: number = 1500;

/** 表示日志格式化所需的房间事件字段。 */
interface LoggedRoomEvent {

  /** 房间信令事件名称 */
  event?: string;
}

/** 保存远端截图请求的流标识、超时任务和结果回调。 */
class RemoteSnapshotRequest {

  /** 截图超时与目标流 */
  timer: number = -1;
  readonly streamKey: string;

  /** 截图结果通知 */
  /**
   * 完成当前资源或媒体结果的异步等待。
   *
   * @param pixelMap 截图结果，由接收方负责释放。
   * @returns 无返回值。
   */
  readonly resolve: (pixelMap: image.PixelMap) => void;
  /**
   * 以指定错误结束当前媒体结果的异步等待。
   *
   * @param error 导致当前等待或媒体输出失败的 SDK 错误。
   * @returns 无返回值。
   */
  readonly reject: (error: XmaxError) => void;

  /**
   * 创建远端截图等待记录。
   *
   * @param streamKey 由房间与用户标识组成的远端流键。
   * @param resolve 操作成功时完成等待的回调。
   * @param reject 操作失败时拒绝等待的回调。
   * @returns 新建的 RemoteSnapshotRequest 实例。
   */
  constructor(
    streamKey: string,
    resolve: (pixelMap: image.PixelMap) => void,
    reject: (error: XmaxError) => void
  ) {
    this.streamKey = streamKey;
    this.resolve = resolve;
    this.reject = reject;
  }
}

/** 封装第三方 RTC 引擎、房间、媒体传输和渲染绑定能力。 */
export class RtcManager implements RtcManaging {

  /** 平台上下文与引擎资源 */
  private readonly context: common.UIAbilityContext;

  /** 远端发布流记录 */
  private readonly remoteStreamKeys: Map<string, RemoteStreamKey> = new Map();

  /** 引擎租约与房间生命周期 */
  private engineLease: RtcEngineLease | null = null;
  private room: RTCRoom | null = null;
  private pendingRoom: RTCRoom | null = null;
  /**
   * 取消当前尚未完成的 RTC 入房等待。
   *
   * @returns 无返回值。
   */
  private pendingJoinCancellation: (() => void) | null = null;

  /** 房间业务事件监听 */
  private listener: RtcEventListener | null = null;

  /** 远端首帧渲染通知 */
  private remoteVideoRenderedListener: RtcRemoteVideoRenderedListener | null = null;
  private readonly renderedRemoteStreams: Set<string> = new Set();

  /** 逐帧观察与数据交付 */
  private remoteVideoFrameListener: RtcRemoteVideoFrameListener | null = null;
  private readonly observedRemoteStreams: Set<string> = new Set();

  /** 远端截图等待 */
  private readonly snapshotRequests: Map<number, RemoteSnapshotRequest> = new Map();

  /** 网络与性能监控 */
  private qualityListener: RtcQualityListener | null = null;

  /** 本地视频镜像配置 */
  private localVideoMirrorType: MirrorType = MirrorType.kMirrorTypeNone;

  /** 当前房间身份 */
  private activeRoomId: string = '';

  /**
   * 创建 RTC Manager。
   *
   * @param context 创建 RTC Engine 使用的平台上下文。
   * @returns 新建的 RtcManager 实例。
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

    const lease: RtcEngineLease = await RtcEngineManager.acquire(this.context);
    const engine: RTCEngine = lease.engine;

    engine.on('onSEIMessageReceived', (key: RemoteStreamKey, message: ArrayBuffer): void => {
      if (this.engine !== engine || key.room_id !== this.activeRoomId ||
        key.stream_index !== StreamIndex.kStreamIndexMain) {
        return;
      }

      const stream = new RemoteStream(key.room_id, key.user_id);
      const decodedMessage: string = util.TextDecoder.create().decodeToString(new Uint8Array(message));
      this.remoteStreamKeys.set(stream.key(), key);
      this.listener?.onSeiMessageReceived(stream, decodedMessage);
    });
    engine.on('onFirstRemoteVideoFrameRendered',
      (key: RemoteStreamKey, _info: VideoFrameInfo): void => {
        if (this.engine !== engine || key.room_id !== this.activeRoomId ||
          key.stream_index !== StreamIndex.kStreamIndexMain) {
          return;
        }
        const stream = new RemoteStream(key.room_id, key.user_id);
        this.renderedRemoteStreams.add(stream.key());
        this.remoteVideoRenderedListener?.(stream);
      });
    engine.on('onRemoteVideoFrame',
      (key: RemoteStreamKey, position: RemoteVideoSinkPosition, frame: IVideoFrame): void => {
        if (this.engine !== engine || key.room_id !== this.activeRoomId ||
          key.stream_index !== StreamIndex.kStreamIndexMain ||
          position !== RemoteVideoSinkPosition.kRemoteVideoSinkPositionAfterPostProcess ||
          frame.width <= 0 || frame.height <= 0) {
          return;
        }
        const stream = new RemoteStream(key.room_id, key.user_id);
        if (this.observedRemoteStreams.has(stream.key())) {
          this.remoteVideoFrameListener?.(stream, () => RtcVideoConverter.copyRemoteFrame(frame));
        }
      });
    engine.on('onTakeRemoteSnapshotResult',
      (taskId: number, key: RemoteStreamKey, pixelMap: image.PixelMap | null, errorCode: number): void => {
        const request: RemoteSnapshotRequest | undefined = this.snapshotRequests.get(taskId);
        if (this.engine !== engine || request === undefined ||
          request.streamKey !== new RemoteStream(key.room_id, key.user_id).key() ||
          key.stream_index !== StreamIndex.kStreamIndexMain) {
          this.releaseSnapshot(pixelMap);
          return;
        }
        this.snapshotRequests.delete(taskId);
        clearTimeout(request.timer);
        if (errorCode !== 0 || pixelMap === null) {
          this.releaseSnapshot(pixelMap);
          request.reject(new XmaxError(XmaxErrorCode.RTC_ERROR, `Remote snapshot failed: ${errorCode}`));
          return;
        }
        request.resolve(pixelMap);
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

        VolcRtcStatsLogger.logPerformanceAlarm(reason, data);
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
    this.renderedRemoteStreams.clear();
    this.observedRemoteStreams.clear();

    try {
      await this.leaveRoom();
    } finally {
      if (lease !== null) {
        const engine: RTCEngine = lease.engine;
        try {
          this.offEngineEventSafely((): void => {
            engine.off('onSEIMessageReceived');
          }, 'onSEIMessageReceived');
          this.offEngineEventSafely((): void => {
            engine.off('onFirstRemoteVideoFrameRendered');
          }, 'onFirstRemoteVideoFrameRendered');
          this.offEngineEventSafely((): void => {
            engine.off('onRemoteVideoFrame');
          }, 'onRemoteVideoFrame');
          this.offEngineEventSafely((): void => {
            engine.off('onTakeRemoteSnapshotResult');
          }, 'onTakeRemoteSnapshotResult');
          this.offEngineEventSafely((): void => {
            engine.off('onPerformanceAlarms');
          }, 'onPerformanceAlarms');
        } finally {
          await RtcEngineManager.release(lease);
        }
      }
    }
  }

  /**
   * 单个事件解绑失败只记日志，不影响其余解绑和引擎释放。
   *
   * @param action 正在执行的资源操作名称或操作函数。
   * @param eventName 需要解绑或记录的事件名称。
   * @returns 无返回值。
   */
  private offEngineEventSafely(action: () => void, eventName: string): void {
    try {
      action();
    } catch (error) {
      XmaxLogger.error(
        `${XmaxLogger.localized("解绑 RTC 事件失败 (Failed to Unbind RTC Event)\n└─ 事件：", "Failed to Unbind RTC Event\n└─ Event: ")}${eventName}${XmaxLogger.localized("\n└─ 原因：", "\n└─ Reason: ")}${XmaxError.from(error).message}`,
        'RTC'
      );
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
      encoder_preference: RtcVideoConverter.convertEncoderPreference(configuration.encoderPreference)
    };
    this.checkResult(
      engine.setVideoEncoderConfig(encoderConfiguration),
      'setVideoEncoderConfig'
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
   * 选择 RTC 内部音频源并启动麦克风采集，调用前须已取得麦克风权限。
   *
   * @returns 无返回值。
   */
  startMicrophoneCapture(): void {
    this.startAudioSource(AudioSourceType.kAudioSourceTypeInternal);
  }

  /**
   * 停止 RTC 麦克风采集。
   *
   * @returns 无返回值。
   */
  stopMicrophoneCapture(): void {
    this.stopAudioCapture();
  }

  /**
   * 启动 RTC 外部音频源。
   *
   * @returns 无返回值。
   */
  startExternalAudioSource(): void {
    this.startAudioSource(AudioSourceType.kAudioSourceTypeExternal);
  }

  /**
   * 停止 RTC 外部音频源。
   *
   * @returns 无返回值。
   */
  stopExternalAudioSource(): void {
    this.stopAudioCapture();
  }

  /**
   * 显式选择音频来源，避免相机麦克风与文件 PCM 输入互相沿用配置。
   *
   * @param source 媒体输入类型，用于选择尺寸处理规则。
   * @returns 无返回值。
   */
  private startAudioSource(source: AudioSourceType): void {
    const engine: RTCEngine = this.requireEngine();
    this.checkResult(engine.setAudioSourceType(source), 'setAudioSourceType');
    this.checkResult(engine.startAudioCapture(), 'startAudioCapture');
  }

  /**
   * 停止当前音频采集通道；引擎已经销毁时无需操作。
   *
   * @returns 无返回值。
   */
  private stopAudioCapture(): void {
    const engine: RTCEngine | null = this.engine;
    if (engine !== null) {
      this.checkResult(engine.stopAudioCapture(), 'stopAudioCapture');
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
        `${XmaxLogger.localized("推送外部视频帧失败 (External Video Frame Push Failed)\n└─ 返回码：", "推送外部视频帧失败 (External Video Frame Push Failed)\n└─ Return Code: ")}${result}`,
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
        `${XmaxLogger.localized("推送外部音频帧失败 (External Audio Frame Push Failed)\n└─ 返回码：", "推送外部音频帧失败 (External Audio Frame Push Failed)\n└─ Return Code: ")}${result}`,
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
    this.snapshotRequests.forEach((request: RemoteSnapshotRequest): void => {
      clearTimeout(request.timer);
      request.reject(new XmaxError(XmaxErrorCode.CANCELLED, 'RTC room closed during snapshot'));
    });
    this.snapshotRequests.clear();
    const room: RTCRoom | null = this.room;
    const pendingRoom: RTCRoom | null = this.pendingRoom;
    const cancelPendingJoin: (() => void) | null = this.pendingJoinCancellation;

    this.room = null;
    this.pendingRoom = null;
    this.pendingJoinCancellation = null;
    this.activeRoomId = '';
    this.remoteStreamKeys.clear();
    this.renderedRemoteStreams.clear();
    this.observedRemoteStreams.clear();

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
    if (!subscribe) {
      // 重新订阅将产生新的首帧渲染事件，上一轮记录不能让新任务提前显示旧画面。
      this.renderedRemoteStreams.delete(new RemoteStream(this.activeRoomId, userId).key());
    }
  }

  /**
   * 更新指定远端用户的音频订阅状态。
   *
   * @param userId 远端用户标识。
   * @param subscribe 是否订阅音频流。
   * @returns 无返回值。
   */
  subscribeRemoteAudio(
    userId: string,
    subscribe: boolean
  ): void {
    this.checkResult(
      this.requireRoom().subscribeStreamAudio(userId, subscribe),
      'subscribeStreamAudio'
    );
  }

  /**
   * 设置指定远端用户的音频播放音量。
   *
   * @param userId 远端用户标识。
   * @param volume RTC 音量值，100 表示原始音量。
   * @returns 无返回值。
   */
  setRemoteAudioVolume(
    userId: string,
    volume: number
  ): void {
    const key: RemoteStreamKey = {
      room_id: this.activeRoomId,
      user_id: userId,
      stream_index: StreamIndex.kStreamIndexMain
    };
    this.checkResult(
      this.requireEngine().setRemoteAudioPlaybackVolume(key, volume),
      'setRemoteAudioPlaybackVolume'
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
   * 使用 RTC 原生截图；调用方负责释放返回的 PixelMap。
   *
   * @param stream 需要绑定或处理的媒体流。
   * @returns 截图完成后返回由调用方负责释放的 PixelMap；超时或失败时拒绝的 Promise。
   */
  takeRemoteSnapshot(stream: RemoteStream): Promise<image.PixelMap> {
    const key: RemoteStreamKey | undefined = this.remoteStreamKeys.get(stream.key());
    if (key === undefined || key.room_id !== this.activeRoomId) {
      return Promise.reject(new XmaxError(XmaxErrorCode.RTC_ERROR, 'Remote stream is unavailable'));
    }
    return new Promise<image.PixelMap>((
      resolve: (pixelMap: image.PixelMap) => void,
      reject: (error: XmaxError) => void
    ): void => {
      const taskId: number = this.requireEngine().takeRemoteSnapshot(key);
      if (taskId <= 0) {
        reject(new XmaxError(XmaxErrorCode.RTC_ERROR, `takeRemoteSnapshot failed: ${taskId}`));
        return;
      }
      const request = new RemoteSnapshotRequest(stream.key(), resolve, reject);
      this.snapshotRequests.set(taskId, request);
      request.timer = setTimeout((): void => {
        if (this.snapshotRequests.get(taskId) !== request) {
          return;
        }
        this.snapshotRequests.delete(taskId);
        request.reject(new XmaxError(XmaxErrorCode.TIMEOUT, 'Remote snapshot timed out'));
      }, SNAPSHOT_TIMEOUT_MS);
    });
  }

  /**
   * 释放不再使用的远端截图，避免持有图像内存。
   *
   * @param pixelMap 需要持有或释放的平台图像对象。
   * @returns 无返回值。
   */
  private releaseSnapshot(pixelMap: image.PixelMap | null): void {
    if (pixelMap !== null) {
      void pixelMap.release().catch((error: Object): void => {
        XmaxLogger.error(`Failed to release RTC snapshot: ${XmaxError.from(error).message}`, 'RTC');
      });
    }
  }

  /**
   * 监听 RTC 已将远端首帧渲染到视图的事件。
   *
   * @param listener 接收事件的监听器；可空接口传入 null 时清除监听器。
   * @returns 无返回值。
   */
  setRemoteVideoRenderedListener(listener: RtcRemoteVideoRenderedListener | null): void {
    this.remoteVideoRenderedListener = listener;
  }

  /**
   * 当前发布周期是否曾成功渲染首帧，用于同一流重新挂载视图。
   *
   * @param stream 需要绑定或处理的媒体流。
   * @returns 指定流在当前发布周期已成功渲染首帧时返回 true。
   */
  hasRenderedRemoteVideo(stream: RemoteStream): boolean {
    return this.renderedRemoteStreams.has(stream.key());
  }

  /**
   * 监听解码及后处理完成的远端帧，不依赖 Surface 是否挂载。
   *
   * @param listener 接收事件的监听器；可空接口传入 null 时清除监听器。
   * @returns 无返回值。
   */
  setRemoteVideoFrameListener(listener: RtcRemoteVideoFrameListener | null): void {
    this.remoteVideoFrameListener = listener;
  }

  /**
   * 按需启停远端帧回调；首帧确认后关闭以避免持续传输像素数据到 ArkTS。
   *
   * @param stream 需要绑定或处理的媒体流。
   * @param enabled 是否开启该能力。
   * @returns 无返回值。
   */
  observeRemoteVideoFrames(stream: RemoteStream, enabled: boolean): void {
    const streamId: string = stream.key();
    if (!enabled && !this.observedRemoteStreams.delete(streamId)) {
      return;
    }
    const key: RemoteStreamKey | undefined = this.remoteStreamKeys.get(streamId);
    if (key === undefined || this.engine === null) {
      if (!enabled) {
        return;
      }
      throw new XmaxError(XmaxErrorCode.RTC_ERROR, 'Remote stream is unavailable');
    }
    if (enabled && this.observedRemoteStreams.has(streamId)) {
      return;
    }
    if (enabled) {
      this.observedRemoteStreams.add(streamId);
    }
    try {
      this.checkResult(this.engine.setRemoteVideoSinkWithConfig(key, {
        position: RemoteVideoSinkPosition.kRemoteVideoSinkPositionAfterPostProcess,
        pixel_format: VideoPixelFormat.kVideoPixelFormatI420,
        apply_rotation: VideoApplyRotation.kVideoApplyRotationDefault,
        mirror_type: VideoSinkMirrorType.kVideoSinkMirrorTypeOFF
      }, enabled), 'setRemoteVideoSinkWithConfig');
    } catch (error) {
      this.observedRemoteStreams.delete(streamId);
      throw XmaxError.from(error);
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
    room.on('onRoomMessageReceived', (_userId: string, message: string): void => {
      this.logReceivedRoomSignal(room, message);
    });
    room.on('onUserMessageReceived', (_userId: string, message: string): void => {
      this.logReceivedRoomSignal(room, message);
    });

    room.on(
      'onUserPublishStreamAudio',
      (_roomId: string, userId: string, published: boolean): void => {
        if (this.room !== room) {
          return;
        }

        this.listener?.onRemoteAudioPublished(userId, published);
      }
    );

    room.on(
      'onUserPublishStreamVideo',
      (_roomId: string, userId: string, published: boolean): void => {
        if (this.room !== room) {
          return;
        }

        if (!published) {
          this.renderedRemoteStreams.delete(new RemoteStream(this.activeRoomId, userId).key());
        }
        this.listener?.onRemoteVideoPublished(userId, published);
      }
    );

    room.on('onLocalStreamStats', (stats: LocalStreamStats): void => {
      if (this.room !== room) {
        return;
      }

      if (!stats.is_screen) {
        const statistics: UplinkVideoStatistics = RtcQualityConverter.uplinkVideoStatistics(stats.video_stats);
        RtcStatsLogger.logUplinkVideoStatistics(statistics);
        this.qualityListener?.onUplinkVideoStatistics(statistics);
      }
    });

    room.on('onRemoteStreamStats', (stats: RemoteStreamStats): void => {
      if (this.room !== room) {
        return;
      }

      if (!stats.is_screen) {
        const statistics: DownlinkVideoStatistics = RtcQualityConverter.downlinkVideoStatistics(stats.uid, stats.video_stats);
        RtcStatsLogger.logDownlinkVideoStatistics(statistics);
        this.qualityListener?.onDownlinkVideoStatistics(statistics);
      }
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

        VolcRtcStatsLogger.logNetworkQuality(localQuality, remoteQualities);
        this.emitNetworkQuality(localQuality, remoteQualities);
      }
    );
  }

  /**
   * 记录当前房间收到的业务信令，供接入方查看事件类型与内容。
   *
   * @param room 当前 RTC 房间实例。
   * @param message 日志内容、错误说明或收到的信令文本。
   * @returns 无返回值。
   */
  private logReceivedRoomSignal(room: RTCRoom, message: string): void {
    if (this.room !== room && this.pendingRoom !== room) {
      return;
    }
    XmaxLogger.debug((): string => {
      try {
        const event = JSON.parse(message) as LoggedRoomEvent;
        const eventType: string = event.event ?? 'unknown';
        const formattedMessage: string = JSON.stringify(event, null, 2);
        const indentedMessage: string = formattedMessage.replace(/\n/g, '\n   ');
        return `${XmaxLogger.localized("接收房间信令 (Receive Room Signal)\n├─ 类型：", "接收房间信令 (Receive Room Signal)\n├─ Type: ")}${eventType}${XmaxLogger.localized("\n└─ 内容：\n   ", "\n└─ Content: \n   ")}${indentedMessage}`;
      } catch (_error) {
        return `${XmaxLogger.localized("接收房间信令 (Receive Room Signal)\n└─ 内容：", "接收房间信令 (Receive Room Signal)\n└─ Content: ")}${message}`;
      }
    }, 'Room');
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
      const result: number = room.joinRoom(token, userInfo, true, configuration);
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
