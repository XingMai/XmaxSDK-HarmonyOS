//
//  RoomJoinConfiguration.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/** 加入 RTC 房间所需的房间标识、用户标识和访问令牌。 */
export class RoomJoinConfiguration {

  /** RTC 房间身份与访问凭证 */
  readonly roomId: string;
  readonly userId: string;
  readonly token: string;

  /**
   * 创建RTC 入房配置。
   *
   * @param roomId RTC 房间标识。
   * @param userId RTC 用户标识。
   * @param token 加入 RTC 房间的访问令牌。
   * @returns 新建的 RoomJoinConfiguration 实例。
   */
  constructor(
    roomId: string,
    userId: string,
    token: string
  ) {
    this.roomId = roomId;
    this.userId = userId;
    this.token = token;
  }
}
