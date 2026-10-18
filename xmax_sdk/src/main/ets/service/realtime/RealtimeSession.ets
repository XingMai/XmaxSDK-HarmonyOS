//
//  RealtimeSession.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { RealtimeSessionConnection } from './RealtimeSessionConnection';

/** 记录服务端实时会话及其 RTC 连接参数和关闭原因。 */
export class RealtimeSession {

  /** 会话身份与当前状态 */
  readonly id: string;
  readonly userId?: string;
  readonly status?: string;

  /** RTC 连接与关闭信息 */
  readonly connection?: RealtimeSessionConnection;
  readonly closeReason?: string;

  /**
   * 创建服务端实时会话记录。
   *
   * @param id 当前资源的唯一标识。
   * @param userId RTC 用户标识。
   * @param status 会话状态或设备性能状态。
   * @param connection 加入实时会话所需的 RTC 连接参数。
   * @param closeReason 服务端会话关闭原因；会话未关闭时可省略。
   * @returns 新建的 RealtimeSession 实例。
   */
  constructor(
    id: string,
    userId?: string,
    status?: string,
    connection?: RealtimeSessionConnection,
    closeReason?: string
  ) {
    this.id = id;
    this.userId = userId;
    this.status = status;
    this.connection = connection;
    this.closeReason = closeReason;
  }
}
