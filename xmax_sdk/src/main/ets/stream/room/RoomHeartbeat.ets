//
//  RoomHeartbeat.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import { RtcManaging } from '../../foundation/rtc/RtcManaging';
import { RoomEvent } from './RoomEvent';

const HEARTBEAT_INTERVAL_MS: number = 10000;

/** Sends periodic room heartbeats and releases its timer on stopping. */
export class RoomHeartbeat {

  /** The adapter for RTC engine, room, and media services. */
  private readonly rtcManager: RtcManaging;

  /** The active room heartbeat timer. */
  private timerId: number = -1;

  /** The local room user identifier. */
  private userId: string = '';

  /** Creates a room heartbeat scheduler. */
  constructor(
    rtcManager: RtcManaging
  ) {
    this.rtcManager = rtcManager;
  }

  /**
   * Starts periodic room heartbeats for the local user.
   *
   * @param userId The RTC user identifier.
   */
  start(
    userId: string
  ): void {
    this.stop();
    this.userId = userId;

    this.timerId = setInterval(
      (): void => {
        if (this.userId.length === 0) {
          return;
        }

        try {
          this.rtcManager.sendRoomMessage(RoomEvent.heartbeat(this.userId));
        } catch (error) {
          const reason: string = error instanceof Error ? error.message : String(error);
          XmaxLogger.error(
            `${XmaxLogger.localized("发送房间心跳失败 (Failed to Send Room Heartbeat)\n└─ 原因：", "发送房间心跳失败 (Failed to Send Room Heartbeat)\n└─ Reason: ")}${reason}`,
            'Room'
          );
        }
      },
      HEARTBEAT_INTERVAL_MS
    );
  }

  /** Stops room heartbeats and releases the timer. */
  stop(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }

    this.userId = '';
  }
}
