//
//  RoomHeartbeat.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import { RtcManaging } from '../../foundation/rtc/RtcManaging';
import { RoomEvent } from './RoomEvent';

const HEARTBEAT_INTERVAL_MS: number = 10000;

/** 定期发送房间业务心跳，并在停止时释放定时器。 */
export class RoomHeartbeat {

  /** 房间传输依赖 */
  private readonly rtcManager: RtcManaging;

  /** 心跳调度与用户身份 */
  private timerId: number = -1;
  private userId: string = '';

  /**
   * 创建RoomHeartbeat。
   *
   * @param rtcManager 提供音视频采集、发布和订阅能力的 RTC 组件。
   * @returns 新建的 RoomHeartbeat 实例。
   */
  constructor(rtcManager: RtcManaging) {
    this.rtcManager = rtcManager;
  }

  /**
   * 为本地用户启动周期性房间心跳。
   *
   * @param userId RTC 用户标识。
   * @returns 无返回值。
   */
  start(userId: string): void {
    this.stop();
    this.userId = userId;

    this.timerId = setInterval((): void => {
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
    }, HEARTBEAT_INTERVAL_MS);
  }

  /**
   * 停止房间心跳并释放定时器。
   *
   * @returns 无返回值。
   */
  stop(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }

    this.userId = '';
  }
}
