import {
  XmaxError,
  XmaxErrorCode
} from '../../foundation/errors/XmaxError';
import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import { RtcProviding } from '../../foundation/rtc/RtcProviding';
import { VideoContentMode } from '../../foundation/media/video/VideoContentMode';
import { InteractionControlling } from '../../media/interaction/InteractionControlling';
import { TrajectoryBinding } from '../../rendering/trajectory/TrajectoryBinding';
import { TrajectoryRegistry } from '../../rendering/trajectory/TrajectoryRegistry';
import { RemoteVideoControlling } from '../../rendering/video/RemoteVideoControlling';
import {
  VideoRenderBinding,
  VideoRenderRegistry
} from '../../rendering/video/VideoRenderRegistry';
import { ApiServicing } from '../../service/network/ApiServicing';
import { RealtimeMediaStream } from '../../service/realtime/RealtimeMediaStream';
import { RealtimeSession } from '../../service/realtime/RealtimeSession';
import { RealtimeSessionConnection } from '../../service/realtime/RealtimeSessionConnection';
import { RealtimeSessionService } from '../../service/realtime/RealtimeSessionService';
import { RealtimeSessionServicing } from '../../service/realtime/RealtimeSessionServicing';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import {
  RealtimeVideoTrack,
  updateRealtimeVideoTrackFormat
} from '../../service/realtime/RealtimeVideoTrack';
import { RoomControlling } from '../../transport/room/RoomControlling';
import { StreamControlling } from '../../transport/stream/StreamControlling';
import { StreamId } from '../../transport/stream/StreamId';

type ConnectionValidity = () => boolean;
type ConnectionHeartbeatFailureHandler = (
  sessionId: string,
  error: XmaxError
) => Promise<void>;

/** 协调服务端会话、RTC 房间、本地发布和远端媒体资源。 */
export class XmaxRealtimeConnectionManager {

  // 基础层组件
  private readonly rtcProvider: RtcProviding;

  // 服务层组件
  private readonly sessionService: RealtimeSessionServicing;

  // 业务层组件
  private readonly interactionController: InteractionControlling;
  private readonly roomController: RoomControlling;
  private readonly remoteVideoController: RemoteVideoControlling;
  private readonly streamController: StreamControlling;

  // 连接资源
  private activeRemoteTrack: RealtimeVideoTrack | null = null;
  private activeSession: RealtimeSession | null = null;

  /**
   * 创建实时连接 Manager。
   *
   * @param rtcProvider RTC 引擎和渲染库等基础能力。
   * @param apiService 创建、心跳和关闭服务端会话的网络服务。
   * @param interactionController 远端轨迹交互使用的业务组件。
   * @param roomController RTC 房间生命周期和房间消息组件。
   * @param remoteVideoController 远端视频绑定组件。
   * @param streamController 本地发布、远端订阅和媒体传输组件。
   */
  constructor(
    rtcProvider: RtcProviding,
    apiService: ApiServicing,
    interactionController: InteractionControlling,
    roomController: RoomControlling,
    remoteVideoController: RemoteVideoControlling,
    streamController: StreamControlling
  ) {
    // 基础层组件
    this.rtcProvider = rtcProvider;

    // 服务层组件
    this.sessionService = new RealtimeSessionService(apiService);

    // 业务层组件
    this.interactionController = interactionController;
    this.roomController = roomController;
    this.remoteVideoController = remoteVideoController;
    this.streamController = streamController;
  }

  /** @returns 当前活动的服务端会话标识；没有连接时返回空字符串。 */
  get currentSessionId(): string {
    return this.activeSession?.id ?? '';
  }

  /**
   * 更新远端轨道使用的视频格式。
   *
   * @param videoFormat 新的视频格式。
   * @returns 无返回值。
   */
  updateRemoteVideoFormat(videoFormat: RealtimeVideoFormat): void {
    const track: RealtimeVideoTrack | null = this.activeRemoteTrack;
    if (track !== null) {
      updateRealtimeVideoTrackFormat(track, videoFormat);
    }
  }

  /**
   * 创建服务端会话、加入 RTC 房间并发布本地媒体流。
   *
   * @param model 服务端使用的实时生成模型名称。
   * @param videoFormat 本地输入及远端结果使用的视频格式。
   * @param includeLocalAudio 是否同时发布本地音频流。
   * @param isCurrent 判断当前连接操作是否仍然有效的回调。
   * @param onHeartbeatFailure 会话心跳失败时执行的处理回调。
   * @returns 完成连接并注册渲染能力后的远端媒体流。
   */
  async connect(
    model: string,
    videoFormat: RealtimeVideoFormat,
    includeLocalAudio: boolean,
    isCurrent: ConnectionValidity,
    onHeartbeatFailure: ConnectionHeartbeatFailureHandler
  ): Promise<RealtimeMediaStream> {
    let session: RealtimeSession | null = null;
    let sessionActivated: boolean = false;

    try {
      session = await this.sessionService.createSession(model);
      this.ensureCurrent(isCurrent);

      const connection: RealtimeSessionConnection | undefined = session.connection;
      if (connection === undefined) {
        throw new XmaxError(
          XmaxErrorCode.SESSION_ERROR,
          'Session does not contain complete RTC join information'
        );
      }

      await this.roomController.join(
        connection,
        (): void => {
          this.ensureCurrent(isCurrent);
        }
      );
      this.ensureCurrent(isCurrent);

      this.streamController.configureRoom(connection.roomId, connection.botName);
      this.streamController.publishLocalStream(includeLocalAudio);
      this.ensureCurrent(isCurrent);

      this.sessionService.startHeartbeat(session.id, onHeartbeatFailure);

      const remoteTrack = new RealtimeVideoTrack(
        connection.botName ?? 'video-remote',
        videoFormat
      );
      VideoRenderRegistry.register(remoteTrack, new VideoRenderBinding(
        this.rtcProvider.renderLibraryName(),
        (
          viewId: string,
          contentMode: VideoContentMode
        ): void => {
          this.remoteVideoController.attach(viewId, contentMode);
        },
        (viewId: string): void => {
          this.remoteVideoController.detach(viewId);
        }
      ));
      TrajectoryRegistry.register(
        remoteTrack,
        new TrajectoryBinding(this.interactionController)
      );

      this.activeSession = session;
      this.activeRemoteTrack = remoteTrack;
      sessionActivated = true;
      this.ensureCurrent(isCurrent);

      return new RealtimeMediaStream(StreamId.REMOTE, remoteTrack);
    } catch (error) {
      if (isCurrent()) {
        await this.rollbackConnection();
      }

      if (session !== null && !sessionActivated) {
        try {
          await this.sessionService.closeSession(session.id);
        } catch (closeError) {
          const reason: string = closeError instanceof Error ?
            closeError.message : String(closeError);
          XmaxLogger.error(
            `连接回滚关闭会话失败\n└─ 原因：${reason}`,
            'Realtime'
          );
        }
      }

      if (!isCurrent()) {
        throw new XmaxError(XmaxErrorCode.CANCELLED, 'Realtime connection was cancelled');
      }

      throw XmaxError.from(error);
    }
  }

  /**
   * 停止心跳、释放远端资源、退出房间并关闭服务端会话。
   *
   * @param fallbackSessionId 当前会话资源已经丢失时使用的会话标识。
   * @returns 实际完成关闭的会话标识；没有会话时返回空值。
   */
  async disconnect(fallbackSessionId?: string): Promise<string | undefined> {
    const session: RealtimeSession | null = this.activeSession;
    const remoteTrack: RealtimeVideoTrack | null = this.activeRemoteTrack;

    this.activeSession = null;
    this.activeRemoteTrack = null;

    this.sessionService.stopHeartbeat();
    if (remoteTrack !== null) {
      VideoRenderRegistry.unregister(remoteTrack);
      TrajectoryRegistry.unregister(remoteTrack);
    }

    try {
      this.remoteVideoController.reset();
    } catch (error) {
      const reason: string = error instanceof Error ? error.message : String(error);
      XmaxLogger.error(
        `重置远端视频渲染失败\n└─ 原因：${reason}`,
        'Realtime'
      );
    }

    try {
      this.streamController.resetRoom();
    } catch (error) {
      const reason: string = error instanceof Error ? error.message : String(error);
      XmaxLogger.error(
        `重置媒体传输失败\n└─ 原因：${reason}`,
        'Realtime'
      );
    }

    try {
      await this.roomController.leave();
    } catch (error) {
      const reason: string = error instanceof Error ? error.message : String(error);
      XmaxLogger.error(
        `离开实时房间失败\n└─ 原因：${reason}`,
        'Realtime'
      );
    }

    const sessionId: string | undefined = session?.id ?? fallbackSessionId;
    if (sessionId !== undefined) {
      try {
        await this.sessionService.closeSession(sessionId);
      } catch (error) {
        const reason: string = error instanceof Error ? error.message : String(error);
        XmaxLogger.error(
          `关闭实时会话失败\n└─ 原因：${reason}`,
          'Realtime'
        );
      }
    }

    return sessionId;
  }

  /**
   * 回滚尚未完成的连接并释放已经创建的房间和远端资源。
   *
   * @returns 回滚操作完成后的 Promise。
   */
  private async rollbackConnection(): Promise<void> {
    const remoteTrack: RealtimeVideoTrack | null = this.activeRemoteTrack;
    this.activeRemoteTrack = null;

    this.sessionService.stopHeartbeat();
    if (remoteTrack !== null) {
      VideoRenderRegistry.unregister(remoteTrack);
      TrajectoryRegistry.unregister(remoteTrack);
    }
    this.remoteVideoController.reset();
    this.streamController.resetRoom();

    try {
      await this.roomController.leave();
    } catch (error) {
      const reason: string = error instanceof Error ? error.message : String(error);
      XmaxLogger.error(
        `连接回滚离开房间失败\n└─ 原因：${reason}`,
        'Realtime'
      );
    }
  }

  /**
   * 确保连接操作仍然属于当前生命周期。
   *
   * @param isCurrent 判断连接操作是否仍然有效的回调。
   * @returns 无返回值。
   */
  private ensureCurrent(isCurrent: ConnectionValidity): void {
    if (!isCurrent()) {
      throw new XmaxError(XmaxErrorCode.CANCELLED, 'Realtime connection was cancelled');
    }
  }

}
