//
//  RoomJoinConfiguration.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/** The room, user, and token required to join an RTC room. */
export class RoomJoinConfiguration {

  /** The RTC room identifier. */
  readonly roomId: string;

  /** The local RTC user identifier. */
  readonly userId: string;

  /** The token guarding operation validity. */
  readonly token: string;

  /** Creates an RTC room join configuration. */
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
