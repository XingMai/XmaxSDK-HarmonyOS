//
//  RemoteStream.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/** An RTC stream identified by room and remote user. */
export class RemoteStream {

  /** The RTC room identifier. */
  readonly roomId: string;

  /** The remote RTC user identifier. */
  readonly userId: string;

  /** Creates a remote stream identity. */
  constructor(
    roomId: string,
    userId: string
  ) {
    this.roomId = roomId;
    this.userId = userId;
  }

  /**
   * Combines room and user identifiers into a stream lookup key.
   *
   * @returns The remote stream key for mapping and subscriptions.
   */
  key(): string {
    return `${this.roomId}:${this.userId}`;
  }
}
