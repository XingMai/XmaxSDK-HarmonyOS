import {
  XmaxError,
  XmaxErrorCode
} from '../../foundation/errors/XmaxError';
import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import { RoomJoinConfiguration } from '../../foundation/rtc/RoomJoinConfiguration';
import { RtcManaging } from '../../foundation/rtc/RtcManaging';
import { RealtimeContext } from '../../service/realtime/RealtimeContext';
import { RealtimePoint } from '../../service/realtime/RealtimePoint';
import { RealtimeSessionConnection } from '../../service/realtime/RealtimeSessionConnection';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import { RoomEvent } from './RoomEvent';
import { RoomHeartbeat } from './RoomHeartbeat';
import { RoomControlling } from './RoomControlling';

/** 表示日志格式化所需的房间事件字段。 */
interface LoggedRoomEvent {

  event?: string;
}

/** 管理 RTC 房间生命周期、心跳和实时生成信令。 */
export class RoomController implements RoomControlling {

  // 基础层组件
  private readonly rtcManager: RtcManaging;

  // 传输层组件
  private readonly heartbeat: RoomHeartbeat;

  // 房间资源
  private localUserId: string = '';

  /**
   * 创建房间 Controller。
   *
   * @param rtcManager 提供房间连接和消息发送能力的 RTC Manager。
   */
  constructor(rtcManager: RtcManaging) {
    this.rtcManager = rtcManager;
    this.heartbeat = new RoomHeartbeat(rtcManager);
  }

  /**
   * 加入 RTC 房间并启动房间心跳。
   *
   * @param connection 房间连接信息。
   * @param ensureActive 用于确认当前连接操作仍然有效的回调。
   * @returns 加入房间完成后的 Promise。
   */
  async join(
    connection: RealtimeSessionConnection,
    ensureActive: () => void
  ): Promise<void> {
    ensureActive();

    this.heartbeat.stop();
    this.localUserId = '';

    await this.rtcManager.joinRoom(new RoomJoinConfiguration(
      connection.roomId,
      connection.userId,
      connection.token
    ));

    this.localUserId = connection.userId;
    this.heartbeat.start(connection.userId);
  }

  /**
   * 停止心跳并离开 RTC 房间。
   *
   * @returns 离开房间完成后的 Promise。
   */
  async leave(): Promise<void> {
    this.heartbeat.stop();
    this.localUserId = '';

    await this.rtcManager.leaveRoom();
  }

  /**
   * 发送实时生成开始信令。
   *
   * @param taskId 生成任务标识。
   * @param videoFormat 生成视频格式。
   * @param context 实时生成上下文。
   * @returns 无返回值。
   */
  startGeneration(
    taskId: string,
    videoFormat: RealtimeVideoFormat,
    context: RealtimeContext
  ): void {
    this.send(RoomEvent.start(
      this.requireUserId(),
      taskId,
      videoFormat,
      context
    ));
  }

  /**
   * 发送实时生成条件变更信令。
   *
   * @param taskId 生成任务标识。
   * @param conditionVersion 条件版本。
   * @param videoFormat 生成视频格式。
   * @param context 新的实时生成上下文。
   * @returns 无返回值。
   */
  changeGenerationCondition(
    taskId: string,
    conditionVersion: number,
    videoFormat: RealtimeVideoFormat,
    context: RealtimeContext
  ): void {
    this.send(RoomEvent.changeCondition(
      this.requireUserId(),
      taskId,
      conditionVersion,
      videoFormat,
      context
    ));
  }

  /**
   * 尝试发送实时生成停止信令。
   *
   * @param taskId 生成任务标识。
   * @returns 无返回值。
   */
  stopGeneration(taskId: string): void {
    if (taskId.length === 0 || this.localUserId.length === 0) {
      return;
    }

    try {
      this.send(RoomEvent.stop(this.localUserId, taskId));
    } catch (error) {
      const reason: string = error instanceof Error ? error.message : String(error);
      XmaxLogger.error(
        `发送生成停止消息失败\n└─ 原因：${reason}`,
        'Room'
      );
    }
  }

  /**
   * 发送实时生成任务的交互轨迹。
   *
   * @param taskId 生成任务标识。
   * @param points 模型输入坐标中的轨迹点。
   * @returns 无返回值。
   */
  sendTracks(
    taskId: string,
    points: RealtimePoint[]
  ): void {
    if (taskId.length === 0 || points.length === 0) {
      return;
    }

    this.rtcManager.sendRoomMessage(RoomEvent.tracks(
      this.requireUserId(),
      taskId,
      points
    ));
  }

  /**
   * 发送房间信令并记录结构化日志。
   *
   * @param message 已序列化的房间信令。
   * @returns 无返回值。
   */
  private send(message: string): void {
    this.rtcManager.sendRoomMessage(message);
    XmaxLogger.debug(this.formatSignalLog(message), 'Room');
  }

  /**
   * 将房间信令格式化为便于阅读的日志文本。
   *
   * @param message 已序列化的房间信令。
   * @returns 格式化后的日志文本。
   */
  private formatSignalLog(message: string): string {
    try {
      const event = JSON.parse(message) as LoggedRoomEvent;
      const eventType: string = event.event ?? 'unknown';
      const formattedMessage: string = JSON.stringify(event, null, 2);
      const indentedMessage: string = formattedMessage.replace(/\n/g, '\n   ');

      return `发送房间信令
├─ 类型：${eventType}
└─ 内容：
   ${indentedMessage}`;
    } catch (_error) {
      return `发送房间信令
└─ 内容：${message}`;
    }
  }

  /**
   * 获取当前房间的本地用户标识。
   *
   * @returns 当前本地用户标识。
   */
  private requireUserId(): string {
    if (this.localUserId.length === 0) {
      throw new XmaxError(XmaxErrorCode.RTC_ERROR, 'RTC room is not joined');
    }
    return this.localUserId;
  }
}
