//
//  RealtimeSessionServicing.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { XmaxError } from '../../foundation/errors/XmaxError';
import { RealtimeSession } from './RealtimeSession';

/**
 * 会话心跳失败时接收会话标识和错误的回调。
 *
 * @param sessionId 服务端实时会话标识。
 * @param error 当前操作失败或终止的原因。
 * @returns 操作完成时兑现的 Promise。
 */
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
   * @param model 生成模型名称，用于隔离各模型的历史档位。
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
