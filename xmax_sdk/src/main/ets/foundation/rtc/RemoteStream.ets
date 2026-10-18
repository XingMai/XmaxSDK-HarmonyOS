//
//  RemoteStream.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/** 以房间和用户标识定位远端 RTC 媒体流。 */
export class RemoteStream {

  /** 远端流定位信息 */
  readonly roomId: string;
  readonly userId: string;

  /**
   * 创建远端媒体流标识。
   *
   * @param roomId RTC 房间标识。
   * @param userId RTC 用户标识。
   * @returns 新建的 RemoteStream 实例。
   */
  constructor(
    roomId: string,
    userId: string
  ) {
    this.roomId = roomId;
    this.userId = userId;
  }

  /**
   * 组合房间与用户标识，生成远端流的查找键。
   *
   * @returns 用于映射和订阅记录的远端流键。
   */
  key(): string {
    return `${this.roomId}:${this.userId}`;
  }
}
