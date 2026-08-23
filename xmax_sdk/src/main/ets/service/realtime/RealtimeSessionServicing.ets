import { XmaxError } from '../../foundation/errors/XmaxError';
import { RealtimeSession } from './RealtimeSession';

export type RealtimeSessionHeartbeatFailureHandler =
  (
    sessionId: string,
    error: XmaxError
  ) => Promise<void>;

/** 定义实时生成会话的创建、心跳和关闭能力。 */
export interface RealtimeSessionServicing {

  /**
   * 为指定实时生成模型创建会话。
   *
   * @param model 实时生成模型标识。
   * @returns 创建的实时生成会话。
   */
  createSession(model: string): Promise<RealtimeSession>;

  /**
   * 开始维持指定实时会话的心跳。
   *
   * @param sessionId 实时会话标识。
   * @param onFailure 心跳失败回调。
   * @returns 无返回值。
   */
  startHeartbeat(
    sessionId: string,
    onFailure: RealtimeSessionHeartbeatFailureHandler
  ): void;

  /**
   * 停止维持当前实时生成会话的心跳。
   *
   * @returns 无返回值。
   */
  stopHeartbeat(): void;

  /**
   * 关闭指定实时会话。
   *
   * @param sessionId 实时会话标识。
   * @returns 会话关闭后的 Promise。
   */
  closeSession(sessionId: string): Promise<void>;
}
