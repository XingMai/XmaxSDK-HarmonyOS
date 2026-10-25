//
//  RtcManager.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import xmaxVideoNative, { NativeRtcRemoteAudioObserver } from 'libxmax_video.so';
import {
  AudioChannel,
  AudioFrameType,
  AudioFrameCallbackMethod,
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
import { RtcManaging, RtcRemoteAudioFrameListener, RtcRemoteVideoFrameListener, RtcRemoteVideoRenderedListener } from './RtcManaging';
import { RtcAudioConverter, RtcAudioFrameData } from './RtcAudioConverter';
import { RtcRemoteAudioFrame } from './RtcRemoteAudioFrame';
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

/** Room event fields used for log formatting. */
interface LoggedRoomEvent {

  // Room signaling event name

  /** The room signaling event name. */
  event?: string;
}

/** A pending remote snapshot with its stream, timeout, and result handlers. */
class RemoteSnapshotRequest {

  // Snapshot timeout and target stream

  /** The timer scheduling pending event delivery. */
  timer: number = -1;

  /** The room/user key identifying the remote stream. */
  readonly streamKey: string;

  /**
   * Completes an asynchronous resource or media result wait.
   *
   * @param pixelMap The snapshot PixelMap, released by the receiver.
   */
  readonly resolve: (
    pixelMap: image.PixelMap
  ) => void;

  /**
   * Rejects the current media result wait with an error.
   *
   * @param error The SDK error ending the wait or media output.
   */
  readonly reject: (
    error: XmaxError
  ) => void;

  /** Creates a pending remote snapshot. */
  constructor(
    streamKey: string,
    resolve: (
      pixelMap: image.PixelMap
    ) => void,
    reject: (
      error: XmaxError
    ) => void
  ) {
    this.streamKey = streamKey;
    this.resolve = resolve;
    this.reject = reject;
  }
}

/** An adapter for third-party RTC engines, rooms, media transport, and rendering. */
export class RtcManager implements RtcManaging {

  // Platform context and engine resources

  /** The platform context for SDK resources. */
  private readonly context: common.UIAbilityContext;

  // Remote published stream records

  /** The published remote stream identities in the current room. */
  private readonly remoteStreamKeys: Map<string, RemoteStreamKey> = new Map();

  // Engine lease and room lifecycle

  /** The exclusive engine lease held by this RTC manager. */
  private engineLease: RtcEngineLease | null = null;

  /** The current RTC room. */
  private room: RTCRoom | null = null;

  /** The RTC room being joined before connection is committed. */
  private pendingRoom: RTCRoom | null = null;

  /** Cancels the pending RTC room join. */
  private pendingJoinCancellation: (() => void) | null = null;

  // Room event listener

  /** The currently installed event handler. */
  private listener: RtcEventListener | null = null;

  // Remote first-frame display notification

  /** The handler for remote first-frame display events. */
  private remoteVideoRenderedListener: RtcRemoteVideoRenderedListener | null = null;

  /** The remote streams with a rendered first frame in this publication. */
  private readonly renderedRemoteStreams: Set<string> = new Set();

  // Frame observation and delivery

  /** The handler observing processed remote video frames. */
  private remoteVideoFrameListener: RtcRemoteVideoFrameListener | null = null;

  /** The remote streams whose processed frames are observed. */
  private readonly observedRemoteStreams: Set<string> = new Set();

  /** The handler observing individual users' unmixed remote PCM. */
  private remoteAudioFrameListener: RtcRemoteAudioFrameListener | null = null;

  /** The remote streams whose PCM packets may be copied. */
  private readonly observedRemoteAudioStreams: Set<string> = new Set();

  /** The room/user bindings whose audio is currently subscribed by this manager. */
  private readonly subscribedRemoteAudioStreams: Set<string> = new Set();

  /** The native PCM observer retained through RTC engine destruction. */
  private remoteAudioObserver: NativeRtcRemoteAudioObserver | null = null;

  // Pending remote snapshot

  /** The pending remote snapshot requests. */
  private readonly snapshotRequests: Map<number, RemoteSnapshotRequest> = new Map();

  // Network and performance monitoring

  /** The handler for RTC quality and device performance events. */
  private qualityListener: RtcQualityListener | null = null;

  // Local video mirroring configuration

  /** The mirroring applied to local RTC video. */
  private localVideoMirrorType: MirrorType = MirrorType.kMirrorTypeNone;

  // Current room identity

  /** The identifier of the currently joined RTC room. */
  private activeRoomId: string = '';

  /** Creates an RTC manager. */
  constructor(
    context: common.UIAbilityContext
  ) {
    this.context = context;
  }

  /** The engine held by the current lease, or undefined before initialization. */
  private get engine(): RTCEngine | null {
    return this.engineLease?.engine ?? null;
  }

  /**
   * Acquires an exclusive RTC engine lease and binds global events.
   *
   * The Promise fulfills after RTC engine initialization.
   */
  async initialize(): Promise<void> {
    if (this.engineLease !== null) {
      return;
    }

    const lease: RtcEngineLease = await RtcEngineManager.acquire(this.context);
    const engine: RTCEngine = lease.engine;

    engine.on(
      'onSEIMessageReceived',
      (key: RemoteStreamKey, message: ArrayBuffer): void => {
        if (this.engine !== engine || key.room_id !== this.activeRoomId ||
          key.stream_index !== StreamIndex.kStreamIndexMain) {
          return;
        }

        const stream = new RemoteStream(
          key.room_id,
          key.user_id
        );
        const decodedMessage: string = util.TextDecoder.create().decodeToString(new Uint8Array(message));
        this.remoteStreamKeys.set(
          stream.key(),
          key
        );
        this.listener?.onSeiMessageReceived(
          stream,
          decodedMessage
        );
      }
    );

    engine.on(
      'onFirstRemoteVideoFrameRendered',
      (key: RemoteStreamKey, _info: VideoFrameInfo): void => {
        if (this.engine !== engine || key.room_id !== this.activeRoomId ||
          key.stream_index !== StreamIndex.kStreamIndexMain) {
          return;
        }

        const stream = new RemoteStream(
          key.room_id,
          key.user_id
        );
        this.renderedRemoteStreams.add(stream.key());
        this.remoteVideoRenderedListener?.(stream);
      }
    );

    engine.on(
      'onRemoteVideoFrame',
      (key: RemoteStreamKey, position: RemoteVideoSinkPosition, frame: IVideoFrame): void => {
        if (this.engine !== engine || key.room_id !== this.activeRoomId ||
          key.stream_index !== StreamIndex.kStreamIndexMain ||
          position !== RemoteVideoSinkPosition.kRemoteVideoSinkPositionAfterPostProcess ||
          frame.width <= 0 || frame.height <= 0) {
          return;
        }

        const stream = new RemoteStream(
          key.room_id,
          key.user_id
        );
        if (this.observedRemoteStreams.has(stream.key())) {
          this.remoteVideoFrameListener?.(
            stream,
            () => RtcVideoConverter.copyRemoteFrame(frame)
          );
        }
      }
    );

    engine.on(
      'onTakeRemoteSnapshotResult',
      (taskId: number, key: RemoteStreamKey, pixelMap: image.PixelMap | null, errorCode: number): void => {
        const request: RemoteSnapshotRequest | undefined = this.snapshotRequests.get(taskId);
        if (this.engine !== engine || request === undefined ||
          request.streamKey !== new RemoteStream(
            key.room_id,
            key.user_id
          ).key() ||
          key.stream_index !== StreamIndex.kStreamIndexMain) {
          this.releaseSnapshot(pixelMap);
          return;
        }

        this.snapshotRequests.delete(taskId);
        clearTimeout(request.timer);

        if (errorCode !== 0 || pixelMap === null) {
          this.releaseSnapshot(pixelMap);
          request.reject(new XmaxError(
            XmaxErrorCode.RTC_ERROR,
            `Remote snapshot failed: ${errorCode}`
          ));
          return;
        }

        request.resolve(pixelMap);
      }
    );

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

        VolcRtcStatsLogger.logPerformanceAlarm(
          reason,
          data
        );
        this.emitPerformanceAlarm(
          reason,
          data
        );
      }
    );

    this.engineLease = lease;
  }

  /**
   * Leaves the room, detaches global events, and releases the engine lease.
   *
   * The Promise fulfills after RTC resource release.
   */
  async destroy(): Promise<void> {
    const lease: RtcEngineLease | null = this.engineLease;
    this.stopRemoteAudioObservation();
    try {
      this.remoteAudioObserver?.close();
    } catch (error) {
      XmaxLogger.error('Native remote audio observer detach failed: ' + String(error), 'RTC');
    }
    this.engineLease = null;
    this.remoteStreamKeys.clear();
    this.renderedRemoteStreams.clear();
    this.observedRemoteStreams.clear();
    this.subscribedRemoteAudioStreams.clear();

    try {
      await this.leaveRoom();
    } finally {
      if (lease !== null) {
        const engine: RTCEngine = lease.engine;
        try {
          this.offEngineEventSafely(
            (): void => {
              engine.off('onSEIMessageReceived');
            },
            'onSEIMessageReceived'
          );
          this.offEngineEventSafely(
            (): void => {
              engine.off('onFirstRemoteVideoFrameRendered');
            },
            'onFirstRemoteVideoFrameRendered'
          );
          this.offEngineEventSafely(
            (): void => {
              engine.off('onRemoteVideoFrame');
            },
            'onRemoteVideoFrame'
          );
          this.offEngineEventSafely(
            (): void => {
              engine.off('onTakeRemoteSnapshotResult');
            },
            'onTakeRemoteSnapshotResult'
          );
          this.offEngineEventSafely(
            (): void => {
              engine.off('onPerformanceAlarms');
            },
            'onPerformanceAlarms'
          );
        } finally {
          try {
            await RtcEngineManager.release(lease);
          } finally {
            this.remoteAudioObserver = null;
          }
        }
      }
    }
  }

  /**
   * Log individual detach failures and continue remaining detaches and engine release.
   *
   * @param action The resource operation name or function.
   * @param eventName The event name to detach or log.
   */
  private offEngineEventSafely(
    action: () => void,
    eventName: string
  ): void {
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
   * Applies neutral encoder settings to the RTC engine.
   *
   * @param configuration The video encoder configuration.
   */
  configureVideoEncoding(
    configuration: VideoEncodingConfiguration
  ): void {
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

  /** Selects external primary video input and disables RTC mirroring. */
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
   * Selects internal audio and starts microphone capture; microphone permission must already be
   * granted.
   */
  startMicrophoneCapture(): void {
    this.startAudioSource(AudioSourceType.kAudioSourceTypeInternal);
  }

  /** Stops RTC microphone capture. */
  stopMicrophoneCapture(): void {
    this.stopAudioCapture();
  }

  /** Starts external RTC audio input. */
  startExternalAudioSource(): void {
    this.startAudioSource(AudioSourceType.kAudioSourceTypeExternal);
  }

  /** Stops external RTC audio input. */
  stopExternalAudioSource(): void {
    this.stopAudioCapture();
  }

  /**
   * Select audio input explicitly so camera microphone and file PCM do not inherit each other's
   * configuration.
   *
   * @param source The input source selecting media sizing rules.
   */
  private startAudioSource(
    source: AudioSourceType
  ): void {
    const engine: RTCEngine = this.requireEngine();
    this.checkResult(
      engine.setAudioSourceType(source),
      'setAudioSourceType'
    );

    this.checkResult(
      engine.startAudioCapture(),
      'startAudioCapture'
    );
  }

  /** Stops audio capture, returning safely if the engine was destroyed. */
  private stopAudioCapture(): void {
    const engine: RTCEngine | null = this.engine;
    if (engine !== null) {
      this.checkResult(
        engine.stopAudioCapture(),
        'stopAudioCapture'
      );
    }
  }

  /**
   * Updates mirroring for the camera position.
   *
   * @param position The current camera position.
   */
  configureLocalVideoMirror(
    position: CameraPosition
  ): void {
    this.localVideoMirrorType = RtcVideoConverter.convertMirrorType(position);
    if (this.engine !== null) {
      this.checkResult(
        this.engine.setLocalVideoMirrorType(this.localVideoMirrorType),
        'setLocalVideoMirrorType'
      );
    }
  }

  /**
   * Converts and submits an external video frame with optional SEI.
   *
   * @param frame The neutral video frame.
   * @param seiData The metadata sent with the video frame.
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
   * Converts and submits neutral PCM to the RTC engine.
   *
   * @param frame The 10 ms PCM frame.
   */
  pushExternalAudioFrame(
    frame: AudioFrame
  ): void {
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
   * Creates a room, binds its events, and waits for joining.
   *
   * The Promise fulfills after joining the room.
   *
   * @param configuration The room join configuration.
   */
  async joinRoom(
    configuration: RoomJoinConfiguration
  ): Promise<void> {
    const engine: RTCEngine = this.requireEngine();
    if (this.room !== null || this.pendingRoom !== null ||
      this.pendingJoinCancellation !== null) {
      throw new XmaxError(
        XmaxErrorCode.RTC_ERROR,
        'RTC room is already active'
      );
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
      throw new XmaxError(
        XmaxErrorCode.CANCELLED,
        'RTC join room was cancelled'
      );
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
      await this.waitForJoin(
        room,
        configuration.token,
        userInfo,
        roomConfiguration
      );
      if (this.pendingRoom !== room) {
        throw new XmaxError(
          XmaxErrorCode.CANCELLED,
          'RTC join room was cancelled'
        );
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
   * Cancels joining and destroys current room resources.
   *
   * The Promise fulfills after leaving the room.
   */
  async leaveRoom(): Promise<void> {
    this.stopRemoteAudioObservation();
    this.snapshotRequests.forEach((request: RemoteSnapshotRequest): void => {
      clearTimeout(request.timer);
      request.reject(new XmaxError(
        XmaxErrorCode.CANCELLED,
        'RTC room closed during snapshot'
      ));
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
    this.subscribedRemoteAudioStreams.clear();

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

  /** Applies mirroring and publishes primary local video. */
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

  /** Unpublishes primary video if a room exists. */
  unpublishLocalVideo(): void {
    if (this.room !== null) {
      this.room.publishStreamVideo(false);
    }
  }

  /** Publishes local audio. */
  publishLocalAudio(): void {
    this.checkResult(
      this.requireRoom().publishStreamAudio(true),
      'publishStreamAudio'
    );
  }

  /** Unpublishes local audio if a room exists. */
  unpublishLocalAudio(): void {
    if (this.room !== null) {
      this.room.publishStreamAudio(false);
    }
  }

  /**
   * Updates a remote user's video subscription.
   *
   * @param userId The remote user identifier.
   * @param subscribe Whether to subscribe to video.
   */
  subscribeRemoteVideo(
    userId: string,
    subscribe: boolean
  ): void {
    this.checkResult(
      this.requireRoom().subscribeStreamVideo(
        userId,
        subscribe
      ),
      'subscribeStreamVideo'
    );

    if (!subscribe) {
      // Resubscription produces a fresh display event; prior readiness must not reveal old video for a new task.
      this.renderedRemoteStreams.delete(new RemoteStream(
        this.activeRoomId,
        userId
      ).key());
    }
  }

  /**
   * Updates a remote user's audio subscription.
   *
   * @param userId The remote user identifier.
   * @param subscribe Whether to subscribe to audio.
   */
  subscribeRemoteAudio(
    userId: string,
    subscribe: boolean
  ): void {
    const streamId: string = new RemoteStream(
      this.activeRoomId,
      userId
    ).key();
    if (!subscribe) {
      this.subscribedRemoteAudioStreams.delete(streamId);
    }

    this.checkResult(
      this.requireRoom().subscribeStreamAudio(
        userId,
        subscribe
      ),
      'subscribeStreamAudio'
    );
    if (subscribe) {
      this.subscribedRemoteAudioStreams.add(streamId);
    }
  }

  /**
   * Sets a remote user's audio playback volume.
   *
   * @param userId The remote user identifier.
   * @param volume The RTC volume; 100 represents original volume.
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
      this.requireEngine().setRemoteAudioPlaybackVolume(
        key,
        volume
      ),
      'setRemoteAudioPlaybackVolume'
    );
  }

  /**
   * Creates an RTC canvas and binds primary local video.
   *
   * @param viewId The rendering view identifier.
   * @param contentMode The video content mode.
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
      this.requireEngine().setLocalVideoCanvas(
        StreamIndex.kStreamIndexMain,
        canvas
      ),
      'setLocalVideoCanvas'
    );

    this.checkResult(
      this.requireEngine().setLocalVideoMirrorType(this.localVideoMirrorType),
      'setLocalVideoMirrorType'
    );
  }

  /** Detaches primary local video using a hidden canvas. */
  unbindLocalVideo(): void {
    if (this.engine !== null) {
      this.engine.setLocalVideoCanvas(
        StreamIndex.kStreamIndexMain,
        RtcVideoConverter.createHiddenCanvas()
      );
    }
  }

  /**
   * Maps a neutral remote stream into an RTC key and binds its view.
   *
   * @param stream The remote stream information.
   * @param viewId The rendering view identifier.
   * @param contentMode The video content mode.
   */
  bindRemoteVideo(
    stream: RemoteStream,
    viewId: string,
    contentMode: VideoContentMode
  ): void {
    const key: RemoteStreamKey | undefined = this.remoteStreamKeys.get(stream.key());
    if (key === undefined) {
      throw new XmaxError(
        XmaxErrorCode.RTC_ERROR,
        'Remote stream is unavailable'
      );
    }

    this.checkResult(
      this.requireEngine().setRemoteVideoCanvas(
        key,
        RtcVideoConverter.createCanvas(
          viewId,
          contentMode
        )
      ),
      'setRemoteVideoCanvas'
    );
  }

  /**
   * Detaches remote video using a hidden canvas.
   *
   * @param stream The remote stream information.
   */
  unbindRemoteVideo(
    stream: RemoteStream
  ): void {
    const key: RemoteStreamKey | undefined = this.remoteStreamKeys.get(stream.key());
    if (this.engine !== null && key !== undefined) {
      this.engine.setRemoteVideoCanvas(
        key,
        RtcVideoConverter.createHiddenCanvas()
      );
    }
  }

  /**
   * Captures an RTC snapshot. The caller releases the returned PixelMap.
   *
   * @param stream The remote stream identified by room and user.
   *
   * @returns The caller-owned snapshot PixelMap; the Promise rejects on failure or timeout.
   */
  takeRemoteSnapshot(
    stream: RemoteStream
  ): Promise<image.PixelMap> {
    const key: RemoteStreamKey | undefined = this.remoteStreamKeys.get(stream.key());
    if (key === undefined || key.room_id !== this.activeRoomId) {
      return Promise.reject(new XmaxError(
        XmaxErrorCode.RTC_ERROR,
        'Remote stream is unavailable'
      ));
    }

    return new Promise<image.PixelMap>((
      resolve: (
        pixelMap: image.PixelMap
      ) => void,
      reject: (
        error: XmaxError
      ) => void
    ): void => {
      const taskId: number = this.requireEngine().takeRemoteSnapshot(key);
      if (taskId <= 0) {
        reject(new XmaxError(
          XmaxErrorCode.RTC_ERROR,
          `takeRemoteSnapshot failed: ${taskId}`
        ));
        return;
      }

      const request = new RemoteSnapshotRequest(
        stream.key(),
        resolve,
        reject
      );
      this.snapshotRequests.set(
        taskId,
        request
      );
      request.timer = setTimeout(
        (): void => {
          if (this.snapshotRequests.get(taskId) !== request) {
            return;
          }

          this.snapshotRequests.delete(taskId);
          request.reject(new XmaxError(
            XmaxErrorCode.TIMEOUT,
            'Remote snapshot timed out'
          ));
        },
        SNAPSHOT_TIMEOUT_MS
      );
    });
  }

  /**
   * Releases an unused remote snapshot's image memory.
   *
   * @param pixelMap The platform image to retain or release.
   */
  private releaseSnapshot(
    pixelMap: image.PixelMap | null
  ): void {
    if (pixelMap !== null) {
      void pixelMap.release().catch((error: Object): void => {
        XmaxLogger.error(
          `Failed to release RTC snapshot: ${XmaxError.from(error).message}`,
          'RTC'
        );
      });
    }
  }

  /**
   * Observes the first remote frame rendered to a view.
   *
   * @param listener The event handler, or null to remove it.
   */
  setRemoteVideoRenderedListener(
    listener: RtcRemoteVideoRenderedListener | null
  ): void {
    this.remoteVideoRenderedListener = listener;
  }

  /**
   * Returns whether the stream rendered a first frame during this publication, supporting view
   * reattachment.
   *
   * @param stream The remote stream identified by room and user.
   *
   * @returns True if the stream rendered its first frame during the current publication.
   */
  hasRenderedRemoteVideo(
    stream: RemoteStream
  ): boolean {
    return this.renderedRemoteStreams.has(stream.key());
  }

  /**
   * Observes decoded, postprocessed remote frames independently of Surface attachment.
   *
   * @param listener The event handler, or null to remove it.
   */
  setRemoteVideoFrameListener(
    listener: RtcRemoteVideoFrameListener | null
  ): void {
    this.remoteVideoFrameListener = listener;
  }

  /**
   * Enables frame callbacks on demand; disable after first-frame confirmation to avoid continued
   * pixel delivery to ArkTS.
   *
   * @param stream The remote stream identified by room and user.
   * @param enabled Whether to enable this capability.
   */
  observeRemoteVideoFrames(
    stream: RemoteStream,
    enabled: boolean
  ): void {
    const streamId: string = stream.key();
    if (!enabled && !this.observedRemoteStreams.delete(streamId)) {
      return;
    }

    const key: RemoteStreamKey | undefined = this.remoteStreamKeys.get(streamId);
    if (key === undefined || this.engine === null) {
      if (!enabled) {
        return;
      }
      throw new XmaxError(
        XmaxErrorCode.RTC_ERROR,
        'Remote stream is unavailable'
      );
    }
    if (enabled && this.observedRemoteStreams.has(streamId)) {
      return;
    }

    if (enabled) {
      this.observedRemoteStreams.add(streamId);
    }

    try {
      this.checkResult(
        this.engine.setRemoteVideoSinkWithConfig(
          key,
          {
            position: RemoteVideoSinkPosition.kRemoteVideoSinkPositionAfterPostProcess,
            pixel_format: VideoPixelFormat.kVideoPixelFormatI420,
            apply_rotation: VideoApplyRotation.kVideoApplyRotationDefault,
            mirror_type: VideoSinkMirrorType.kVideoSinkMirrorTypeOFF
          },
          enabled
        ),
        'setRemoteVideoSinkWithConfig'
      );
    } catch (error) {
      this.observedRemoteStreams.delete(streamId);
      throw XmaxError.from(error);
    }
  }

  /** Sets the receiver for copied individual-user PCM packets. */
  setRemoteAudioFrameListener(
    listener: RtcRemoteAudioFrameListener | null
  ): void {
    this.remoteAudioFrameListener = listener;
  }

  /** Updates PCM observation without changing audio subscriptions or playback volume. */
  observeRemoteAudioFrames(
    stream: RemoteStream,
    enabled: boolean
  ): void {
    const streamId: string = stream.key();
    if (!enabled) {
      this.observedRemoteAudioStreams.delete(streamId);
      if (this.observedRemoteAudioStreams.size === 0) {
        this.disableRemoteAudioObservation();
      }
      return;
    }

    if (stream.roomId !== this.activeRoomId || this.engine === null) {
      throw new XmaxError(
        XmaxErrorCode.RTC_ERROR,
        'Remote audio stream is unavailable'
      );
    }
    if (this.observedRemoteAudioStreams.has(streamId)) {
      return;
    }

    if (this.observedRemoteAudioStreams.size === 0) {
      const engine: RTCEngine = this.requireEngine();
      try {
        if (this.remoteAudioObserver === null) {
          this.remoteAudioObserver = xmaxVideoNative.createRtcRemoteAudioObserver(
            engine.getNativeHandle(),
            (roomId: string, userId: string, streamIndex: number, data: ArrayBuffer,
              sampleRate: number, channels: number, timestampUs: number, isDiscontinuous: boolean): void => {
              if (this.engine !== engine || roomId !== this.activeRoomId ||
                streamIndex !== StreamIndex.kStreamIndexMain) {
                return;
              }

              const stream: RemoteStream = new RemoteStream(roomId, userId);
              if (!this.observedRemoteAudioStreams.has(stream.key()) ||
                !this.subscribedRemoteAudioStreams.has(stream.key())) {
                return;
              }

              const frame: RtcAudioFrameData = {
                timestamp_us: timestampUs,
                sample_rate: sampleRate,
                channel: channels,
                data: new Uint8Array(data),
                data_size: data.byteLength,
                frame_type: AudioFrameType.kFrameTypePCM16
              };
              this.remoteAudioFrameListener?.(
                stream,
                (): RtcRemoteAudioFrame => RtcAudioConverter.copyRemoteFrame(frame, isDiscontinuous)
              );
            }
          );
        }
        this.remoteAudioObserver.setEnabled(true);
        this.checkResult(
          engine.enableAudioFrameCallback(
            AudioFrameCallbackMethod.kRemoteUser,
            {
              sample_rate: AudioSampleRate.kAudioSampleRateAuto,
              channel: AudioChannel.kAudioChannelAuto,
              samples_per_call: 0
            }
          ),
          'enableAudioFrameCallback'
        );
      } catch (error) {
        this.stopRemoteAudioObservation();
        throw new XmaxError(XmaxErrorCode.RTC_ERROR, XmaxError.from(error).message);
      }
    }

    this.observedRemoteAudioStreams.add(streamId);
  }

  /** Invalidates queued PCM while retaining its observer until the engine lease is released. */
  private disableRemoteAudioObservation(): void {
    const engine: RTCEngine | null = this.engine;
    const observer: NativeRtcRemoteAudioObserver | null = this.remoteAudioObserver;
    if (engine === null || observer === null) {
      return;
    }

    try {
      this.checkResult(
        engine.disableAudioFrameCallback(AudioFrameCallbackMethod.kRemoteUser),
        'disableAudioFrameCallback'
      );
    } finally {
      observer.setEnabled(false);
    }
  }

  /** Rejects queued PCM before best-effort native observation cleanup. */
  private stopRemoteAudioObservation(): void {
    this.observedRemoteAudioStreams.clear();
    try {
      this.disableRemoteAudioObservation();
    } catch (error) {
      XmaxLogger.error(
        'Remote audio frame observation cleanup failed: ' + String(error),
        'RTC'
      );
    }
  }

  /**
   * Returns the RTC Surface rendering library name.
   *
   * @returns The RTC rendering library name.
   */
  renderLibraryName(): string {
    return 'volcenginertc_sdk';
  }

  /**
   * Sends a text message to the current room.
   *
   * @param message The message content.
   */
  sendRoomMessage(
    message: string
  ): void {
    this.checkResult(
      this.requireRoom().sendRoomMessage(message),
      'sendRoomMessage'
    );
  }

  /**
   * Sets media publication and SEI event delivery.
   *
   * @param listener The RTC event listener, or null to remove it.
   */
  setEventListener(
    listener: RtcEventListener | null
  ): void {
    this.listener = listener;
  }

  /**
   * Sets network quality and performance alarm delivery.
   *
   * @param listener The RTC quality listener, or null to remove it.
   */
  setQualityListener(
    listener: RtcQualityListener | null
  ): void {
    this.qualityListener = listener;
  }

  /**
   * Binds room publication, stream statistics, and quality events.
   *
   * @param room The RTC room to observe.
   */
  private bindRoomEvents(
    room: RTCRoom
  ): void {
    room.on(
      'onRoomMessageReceived',
      (userId: string, message: string): void => {
        this.logReceivedRoomSignal(
          room,
          message
        );
        if (this.room === room) {
          this.listener?.onRoomSignalReceived?.(
            userId,
            message
          );
        }
      }
    );

    room.on(
      'onUserMessageReceived',
      (userId: string, message: string): void => {
        this.logReceivedRoomSignal(
          room,
          message
        );
        if (this.room === room) {
          this.listener?.onRoomSignalReceived?.(
            userId,
            message
          );
        }
      }
    );

    room.on(
      'onUserPublishStreamAudio',
      (_roomId: string, userId: string, published: boolean): void => {
        if (this.room !== room) {
          return;
        }

        if (!published) {
          this.subscribedRemoteAudioStreams.delete(new RemoteStream(
            this.activeRoomId,
            userId
          ).key());
        }

        this.listener?.onRemoteAudioPublished(
          userId,
          published
        );
      }
    );

    room.on(
      'onUserPublishStreamVideo',
      (_roomId: string, userId: string, published: boolean): void => {
        if (this.room !== room) {
          return;
        }

        if (!published) {
          this.renderedRemoteStreams.delete(new RemoteStream(
            this.activeRoomId,
            userId
          ).key());
        }

        this.listener?.onRemoteVideoPublished(
          userId,
          published
        );
      }
    );

    room.on(
      'onLocalStreamStats',
      (stats: LocalStreamStats): void => {
        if (this.room !== room) {
          return;
        }

        if (!stats.is_screen) {
          const statistics: UplinkVideoStatistics = RtcQualityConverter.uplinkVideoStatistics(stats.video_stats);
          RtcStatsLogger.logUplinkVideoStatistics(statistics);
          this.qualityListener?.onUplinkVideoStatistics(statistics);
        }
      }
    );

    room.on(
      'onRemoteStreamStats',
      (stats: RemoteStreamStats): void => {
        if (this.room !== room) {
          return;
        }

        if (!stats.is_screen) {
          const statistics: DownlinkVideoStatistics = RtcQualityConverter.downlinkVideoStatistics(
            stats.uid,
            stats.video_stats
          );
          RtcStatsLogger.logDownlinkVideoStatistics(statistics);
          this.qualityListener?.onDownlinkVideoStatistics(statistics);
        }
      }
    );

    room.on(
      'onNetworkQuality',
      (
        localQuality: NetworkQualityStats,
        remoteQualities: NetworkQualityStats[]
      ): void => {
        if (this.room !== room) {
          return;
        }

        VolcRtcStatsLogger.logNetworkQuality(
          localQuality,
          remoteQualities
        );
        this.emitNetworkQuality(
          localQuality,
          remoteQualities
        );
      }
    );
  }

  /**
   * Logs received room signals for inspecting event types and content.
   *
   * @param room The current RTC room instance.
   * @param message The received room signal text.
   */
  private logReceivedRoomSignal(
    room: RTCRoom,
    message: string
  ): void {
    if (this.room !== room && this.pendingRoom !== room) {
      return;
    }

    XmaxLogger.debug(
      (): string => {
        try {
          const event = JSON.parse(message) as LoggedRoomEvent;
          const eventType: string = event.event ?? 'unknown';
          const formattedMessage: string = JSON.stringify(
            event,
            null,
            2
          );
          const indentedMessage: string = formattedMessage.replace(
            /\n/g,
            '\n   '
          );
          return `${XmaxLogger.localized("接收房间信令 (Receive Room Signal)\n├─ 类型：", "接收房间信令 (Receive Room Signal)\n├─ Type: ")}${eventType}${XmaxLogger.localized("\n└─ 内容：\n   ", "\n└─ Content: \n   ")}${indentedMessage}`;
        } catch (_error) {
          return `${XmaxLogger.localized("接收房间信令 (Receive Room Signal)\n└─ 内容：", "接收房间信令 (Receive Room Signal)\n└─ Content: ")}${message}`;
        }
      },
      'Room'
    );
  }

  /**
   * Converts RTC network statistics for the quality listener.
   *
   * @param localQuality The local uplink and downlink statistics.
   * @param remoteQualities The remote users' network quality statistics.
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
   * Converts an RTC performance alarm for the quality listener.
   *
   * @param reason The RTC performance alarm reason.
   * @param data The RTC recommended media configuration.
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
   * Waits for room join events with cancellation and timeout protection.
   *
   * The Promise fulfills after successful joining.
   *
   * @param room The RTC room to join.
   * @param token The room access token.
   * @param userInfo The local user information.
   * @param configuration The room configuration.
   */
  private waitForJoin(
    room: RTCRoom,
    token: string,
    userInfo: UserInfo,
    configuration: RTCRoomConfig
  ): Promise<void> {
    return new Promise((resolve: () => void, reject: (
      reason: XmaxError
    ) => void) => {
      let settled: boolean = false;
      let timerId: number = -1;

      this.pendingJoinCancellation = (): void => {
        if (settled) {
          return;
        }

        settled = true;
        clearTimeout(timerId);
        reject(new XmaxError(
          XmaxErrorCode.CANCELLED,
          'RTC join room was cancelled'
        ));
      };

      timerId = setTimeout(
        (): void => {
          if (!settled) {
            settled = true;
            reject(new XmaxError(
              XmaxErrorCode.TIMEOUT,
              'RTC join room timed out'
            ));
          }
        },
        JOIN_TIMEOUT_MS
      );

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

      const result: number = room.joinRoom(
        token,
        userInfo,
        true,
        configuration
      );
      if (result < 0 && !settled) {
        settled = true;
        clearTimeout(timerId);
        reject(new XmaxError(
          XmaxErrorCode.RTC_ERROR,
          `joinRoom failed: ${result}`
        ));
      }
    });
  }

  /**
   * Returns the initialized RTC engine.
   *
   * @returns The current RTC engine.
   */
  private requireEngine(): RTCEngine {
    if (this.engine === null) {
      throw new XmaxError(
        XmaxErrorCode.RTC_ERROR,
        'RTC engine is not initialized'
      );
    }
    return this.engine;
  }

  /**
   * Returns the joined RTC room.
   *
   * @returns The current RTC room.
   */
  private requireRoom(): RTCRoom {
    if (this.room === null) {
      throw new XmaxError(
        XmaxErrorCode.RTC_ERROR,
        'RTC room is not joined'
      );
    }
    return this.room;
  }

  /**
   * Validates a synchronous RTC return code.
   *
   * @param result The RTC return code.
   * @param operation The RTC operation name.
   */
  private checkResult(
    result: number,
    operation: string
  ): void {
    if (result < 0) {
      throw new XmaxError(
        XmaxErrorCode.RTC_ERROR,
        `${operation} failed: ${result}`
      );
    }
  }

}
