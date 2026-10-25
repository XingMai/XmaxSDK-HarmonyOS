//
//  RealtimeSession.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { RealtimeSessionConnection } from './RealtimeSessionConnection';

/** A server realtime session, RTC connection parameters, and closure reason. */
export class RealtimeSession {

  /** The server session identifier. */
  readonly id: string;

  /** The server user identifier. */
  readonly userId?: string;

  /** The server session status. */
  readonly status?: string;

  /** The RTC connection parameters returned by the server. */
  readonly connection?: RealtimeSessionConnection;

  /** The server session closure reason, if closed. */
  readonly closeReason?: string;

  /** Creates a server session record. */
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
