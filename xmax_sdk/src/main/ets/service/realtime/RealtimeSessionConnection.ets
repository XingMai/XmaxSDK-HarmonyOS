//
//  RealtimeSessionConnection.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/** 提供加入实时会话 RTC 房间及识别生成服务用户所需的参数。 */
export class RealtimeSessionConnection {

  /** 房间与本地用户身份 */
  readonly roomId: string;
  readonly userId: string;

  /** 访问凭证与服务用户名称 */
  readonly token: string;
  readonly botName?: string;

  /**
   * 创建实时会话 RTC 连接配置。
   *
   * @param roomId RTC 房间标识。
   * @param userId RTC 用户标识。
   * @param token 加入 RTC 房间的访问令牌。
   * @param botName 服务端生成用户的识别名称。
   * @returns 新建的 RealtimeSessionConnection 实例。
   */
  constructor(
    roomId: string,
    userId: string,
    token: string,
    botName?: string
  ) {
    this.roomId = roomId;
    this.userId = userId;
    this.token = token;
    this.botName = botName;
  }
}
