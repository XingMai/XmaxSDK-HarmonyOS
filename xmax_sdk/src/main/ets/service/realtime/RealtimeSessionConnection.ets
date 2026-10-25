//
//  RealtimeSessionConnection.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/** The parameters for joining an RTC room and recognizing the generation service user. */
export class RealtimeSessionConnection {

  /** The RTC room identifier. */
  readonly roomId: string;

  /** The local RTC user identifier. */
  readonly userId: string;

  /** The token guarding operation validity. */
  readonly token: string;

  /** The generation service user's name. */
  readonly botName?: string;

  /** Creates a session RTC connection configuration. */
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
