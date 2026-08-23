import {
  XmaxError,
  XmaxErrorCode
} from '../../foundation/errors/XmaxError';
import { ApiServicing } from '../network/ApiServicing';
import { RealtimeSession } from './RealtimeSession';
import { RealtimeSessionConnection } from './RealtimeSessionConnection';
import {
  RealtimeSessionHeartbeatFailureHandler,
  RealtimeSessionServicing
} from './RealtimeSessionServicing';

const SESSION_HEARTBEAT_INTERVAL_MS: number = 10000;

/** 管理实时生成会话的创建、心跳维持和关闭。 */
export class RealtimeSessionService implements RealtimeSessionServicing {

  // 服务层组件
  private readonly apiService: ApiServicing;

  // 运行状态
  private heartbeatTimer: number = -1;
  private heartbeatVersion: number = 0;

  /**
   * 创建实时生成会话 Service。
   *
   * @param apiService 提供会话 API 请求能力的 API Service。
   */
  constructor(apiService: ApiServicing) {
    this.apiService = apiService;
  }

  /**
   * 为指定实时生成模型创建会话。
   *
   * @param model 实时生成模型标识。
   * @returns 创建的实时生成会话。
   */
  async createSession(model: string): Promise<RealtimeSession> {
    const body: Record<string, string> = { 'model': model };
    const value = await this.apiService.post<Object>('/session', body);

    return this.toSession(value, true);
  }

  /**
   * 启动指定会话的周期性心跳。
   *
   * @param sessionId 实时生成会话标识。
   * @param onFailure 心跳失败处理方法。
   * @returns 无返回值。
   */
  startHeartbeat(
    sessionId: string,
    onFailure: RealtimeSessionHeartbeatFailureHandler
  ): void {
    this.stopHeartbeat();

    const heartbeatVersion: number = this.heartbeatVersion;
    this.scheduleHeartbeat(sessionId, onFailure, heartbeatVersion);
  }

  /**
   * 停止当前会话心跳并使已发出的心跳结果失效。
   *
   * @returns 无返回值。
   */
  stopHeartbeat(): void {
    this.heartbeatVersion++;

    if (this.heartbeatTimer >= 0) {
      clearTimeout(this.heartbeatTimer);
      this.heartbeatTimer = -1;
    }
  }

  /**
   * 请求关闭指定实时生成会话。
   *
   * @param sessionId 实时生成会话标识。
   * @returns 会话关闭完成后的 Promise。
   */
  async closeSession(sessionId: string): Promise<void> {
    await this.apiService.delete<Object>(`/session/${sessionId}`);
  }

  /**
   * 安排下一次会话心跳，并在失败时终止当前心跳周期。
   *
   * @param sessionId 实时生成会话标识。
   * @param onFailure 心跳失败处理方法。
   * @param heartbeatVersion 当前心跳周期版本。
   * @returns 无返回值。
   */
  private scheduleHeartbeat(
    sessionId: string,
    onFailure: RealtimeSessionHeartbeatFailureHandler,
    heartbeatVersion: number
  ): void {
    this.heartbeatTimer = setTimeout(async () => {
      this.heartbeatTimer = -1;

      try {
        const session: RealtimeSession = await this.heartbeatSession(sessionId);
        this.ensureSessionActive(session);
      } catch (error) {
        if (heartbeatVersion !== this.heartbeatVersion) {
          return;
        }

        this.stopHeartbeat();
        await onFailure(
          sessionId,
          XmaxError.from(error)
        );

        return;
      }

      if (heartbeatVersion === this.heartbeatVersion) {
        this.scheduleHeartbeat(sessionId, onFailure, heartbeatVersion);
      }
    }, SESSION_HEARTBEAT_INTERVAL_MS);
  }

  /**
   * 发送一次会话心跳并解析最新会话信息。
   *
   * @param sessionId 实时生成会话标识。
   * @returns 心跳响应中的实时生成会话。
   */
  private async heartbeatSession(sessionId: string): Promise<RealtimeSession> {
    const value = await this.apiService.put<Object>(
      `/session/${sessionId}/heartbeat`
    );

    return this.toSession(value, false);
  }

  /**
   * 校验心跳返回的会话是否仍处于活动状态。
   *
   * @param session 心跳返回的实时生成会话。
   * @returns 无返回值。
   */
  private ensureSessionActive(session: RealtimeSession): void {
    if (session.status !== undefined && session.status !== 'ACTIVE') {
      throw new XmaxError(
        XmaxErrorCode.SESSION_ERROR,
        session.closeReason ?? `Session is no longer active: ${session.status}`
      );
    }
  }

  /**
   * 将 API 响应转换为实时生成会话。
   *
   * @param value API 返回的会话数据。
   * @param requiresConnection 是否要求响应包含完整 RTC 连接信息。
   * @returns 转换后的实时生成会话。
   */
  private toSession(
    value: Object,
    requiresConnection: boolean
  ): RealtimeSession {
    const record = JSON.parse(JSON.stringify(value)) as Record<string, Object>;
    const sessionId: string | undefined = this.readString(record, 'sessionUid');

    if (sessionId === undefined) {
      throw new XmaxError(XmaxErrorCode.SESSION_ERROR, 'Invalid session response');
    }

    const userId: string | undefined = this.readString(record, 'userUid');
    const connection: RealtimeSessionConnection | undefined = this.readConnection(
      record['modelExtra'],
      userId
    );

    if (requiresConnection && connection === undefined) {
      throw new XmaxError(
        XmaxErrorCode.SESSION_ERROR,
        'Session does not contain complete RTC join information'
      );
    }

    const status: string | undefined = this.readString(record, 'status');
    const closeReason: string | undefined = this.readString(record, 'closeReason');

    return new RealtimeSession(
      sessionId,
      userId,
      status,
      connection,
      closeReason
    );
  }

  /**
   * 从会话扩展数据中解析 RTC 连接信息。
   *
   * @param raw 原始会话扩展数据。
   * @param fallbackUserId 缺少用户标识时使用的备用值。
   * @returns 完整连接信息；数据不完整时返回空值。
   */
  private readConnection(
    raw: Object | undefined,
    fallbackUserId?: string
  ): RealtimeSessionConnection | undefined {
    if (raw === undefined || raw === null) {
      return undefined;
    }

    let record: Record<string, Object>;
    try {
      if (typeof raw === 'string') {
        record = JSON.parse(raw) as Record<string, Object>;
      } else {
        record = JSON.parse(JSON.stringify(raw)) as Record<string, Object>;
      }
    } catch (_error) {
      return undefined;
    }

    const roomId: string = this.readString(record, 'room_id') ?? '';
    const token: string = this.readString(record, 'room_token') ?? '';
    const userId: string = this.readString(record, 'user_id') ?? fallbackUserId ?? '';
    if (roomId.length === 0 || token.length === 0 || userId.length === 0) {
      return undefined;
    }

    return new RealtimeSessionConnection(
      roomId,
      userId,
      token,
      this.readString(record, 'bot_name')
    );
  }

  /**
   * 读取记录中的非空字符串字段。
   *
   * @param record 数据记录。
   * @param key 字段名称。
   * @returns 规范化后的字符串；字段无效时返回空值。
   */
  private readString(
    record: Record<string, Object>,
    key: string
  ): string | undefined {
    const raw: Object | undefined = record[key];
    return typeof raw === 'string' ? this.nonEmpty(raw) : undefined;
  }

  /**
   * 清理字符串两端空白并过滤空字符串。
   *
   * @param value 待处理字符串。
   * @returns 非空字符串；输入无效时返回空值。
   */
  private nonEmpty(value: string | undefined): string | undefined {
    const normalized: string | undefined = value?.trim();
    return normalized !== undefined && normalized.length > 0 ? normalized : undefined;
  }
}
