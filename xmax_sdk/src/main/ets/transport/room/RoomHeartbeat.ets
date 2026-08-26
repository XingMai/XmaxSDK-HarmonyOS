import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import { RtcManaging } from '../../foundation/rtc/RtcManaging';
import { RoomEvent } from './RoomEvent';

const HEARTBEAT_INTERVAL_MS: number = 10000;

export class RoomHeartbeat {
  // 基础层组件
  private readonly rtcManager: RtcManaging;

  // 运行状态
  private timerId: number = -1;
  private userId: string = '';

  constructor(rtcManager: RtcManaging) {
    this.rtcManager = rtcManager;
  }

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
          `发送房间心跳失败\n└─ 原因：${reason}`,
          'Room'
        );
      }
    }, HEARTBEAT_INTERVAL_MS);
  }

  stop(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }

    this.userId = '';
  }
}
