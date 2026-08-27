import {
  XmaxError,
  XmaxErrorCode
} from '../../foundation/errors/XmaxError';
import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import { MediaControlling } from '../../media/MediaControlling';
import { RenderControlling } from '../../rendering/RenderControlling';
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
import { StreamControlling } from '../../stream/StreamControlling';
import { StreamId } from '../../stream/StreamId';

type ConnectionValidity = () => boolean;
type ConnectionHeartbeatFailureHandler = (
  sessionId: string,
  error: XmaxError
) => Promise<void>;

/** 协调服务端会话、RTC 房间、本地发布和远端媒体资源。 */
export class XmaxRealtimeConnectionManager {

  // 服务层组件
  private readonly sessionService: RealtimeSessionServicing;

  // 业务层组件
  private readonly mediaController: MediaControlling;
  private readonly streamController: StreamControlling;

  // 渲染层组件
  private readonly renderController: RenderControlling;

  // 连接资源
  private activeRemoteTrack: RealtimeVideoTrack | null = null;
  private activeSession: RealtimeSession | null = null;

  /**
   * 创建实时连接 Manager。
   *
   * @param apiService 创建、心跳和关闭服务端会话的网络服务。
   * @param mediaController 远端轨迹交互使用的统一媒体组件。
   * @param renderController 视频轨道、远端画面和轨迹绑定的统一渲染组件。
   * @param streamController RTC 房间、媒体流和信令的统一流组件。
   */
  constructor(
    apiService: ApiServicing,
    mediaController: MediaControlling,
    renderController: RenderControlling,
    streamController: StreamControlling
  ) {
    // 服务层组件
    this.sessionService = new RealtimeSessionService(apiService);

    // 业务层组件
    this.mediaController = mediaController;
    this.streamController = streamController;

    // 渲染层组件
    this.renderController = renderController;
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

      await this.streamController.connect(
        connection,
        includeLocalAudio,
        (): void => {
          this.ensureCurrent(isCurrent);
        }
      );
      this.ensureCurrent(isCurrent);

      this.sessionService.startHeartbeat(session.id, onHeartbeatFailure);

      const remoteTrack = new RealtimeVideoTrack(
        connection.botName ?? 'video-remote',
        videoFormat
      );
      this.renderController.registerRemoteTrack(
        remoteTrack,
        this.mediaController
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
    try {
      this.renderController.resetRemoteTrack(remoteTrack);
    } catch (error) {
      const reason: string = error instanceof Error ? error.message : String(error);
      XmaxLogger.error(
        `重置远端视频渲染失败\n└─ 原因：${reason}`,
        'Realtime'
      );
    }

    try {
      await this.streamController.disconnect();
    } catch (error) {
      const reason: string = error instanceof Error ? error.message : String(error);
      XmaxLogger.error(
        `释放 RTC 传输资源失败\n└─ 原因：${reason}`,
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
    this.renderController.resetRemoteTrack(remoteTrack);
    try {
      await this.streamController.disconnect();
    } catch (error) {
      const reason: string = error instanceof Error ? error.message : String(error);
      XmaxLogger.error(
        `连接回滚释放 RTC 传输资源失败\n└─ 原因：${reason}`,
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
