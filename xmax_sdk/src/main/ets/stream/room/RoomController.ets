//
//  RoomController.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { RealtimeGenerationParameters } from '../../service/realtime/RealtimeGenerationOptions';
import { ImageSize } from '../../service/media/ImageSize';
import { RealtimeTiming } from '../../core/realtime/RealtimeTiming';
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

  /** 房间信令事件名称 */
  event?: string;
}

/** 管理 RTC 房间生命周期、心跳和实时生成信令。 */
export class RoomController implements RoomControlling {

  /** 房间传输、心跳与计时依赖 */
  private readonly rtcManager: RtcManaging;

  /** 流层组件 */
  private readonly heartbeat: RoomHeartbeat;

  private readonly timing: RealtimeTiming;

  /** 本地房间用户身份 */
  private localUserId: string = '';

  /**
   * 创建房间 Controller。
   *
   * @param rtcManager 提供房间连接和消息发送能力的 RTC Manager。
   * @param timing 与实时 Manager 共享的启动耗时记录。
   * @returns 新建的 RoomController 实例。
   */
  constructor(rtcManager: RtcManaging, timing: RealtimeTiming = new RealtimeTiming()) {
    this.timing = timing;
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

    this.timing.beginRoomJoin();
    await this.rtcManager.joinRoom(new RoomJoinConfiguration(
      connection.roomId,
      connection.userId,
      connection.token
    ));

    this.timing.finishRoomJoin();
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
   * @param faceRestoration 是否启用人脸修复。
   * @param targetSize 可选的生成结果流目标尺寸。
   * @param paddingContain 是否保持媒体比例并由服务端补边显示。
   * @param extraParams SDK 内部传递的静态生成配置。
   * @returns 无返回值。
   */
  startGeneration(
    taskId: string,
    videoFormat: RealtimeVideoFormat,
    context: RealtimeContext,
    faceRestoration: boolean = false,
    targetSize?: ImageSize,
    paddingContain: boolean = false,
    extraParams?: RealtimeGenerationParameters
  ): void {
    this.send(RoomEvent.start(
      this.requireUserId(),
      taskId,
      videoFormat,
      context,
      faceRestoration,
      targetSize,
      paddingContain,
      extraParams
    ));
  }

  /**
   * 发送实时生成条件变更信令。
   *
   * @param taskId 生成任务标识。
   * @param videoFormat 生成视频格式。
   * @param context 新的实时生成上下文。
   * @param faceRestoration 是否启用人脸修复。
   * @param targetSize 可选的生成结果流目标尺寸。
   * @param paddingContain 是否保持媒体比例并由服务端补边显示。
   * @param extraParams SDK 内部传递的静态生成配置。
   * @returns 无返回值。
   */
  changeGenerationCondition(
    taskId: string,
    videoFormat: RealtimeVideoFormat,
    context: RealtimeContext,
    faceRestoration: boolean = false,
    targetSize?: ImageSize,
    paddingContain: boolean = false,
    extraParams?: RealtimeGenerationParameters
  ): void {
    this.send(RoomEvent.changeCondition(
      this.requireUserId(),
      taskId,
      videoFormat,
      context,
      faceRestoration,
      targetSize,
      paddingContain,
      extraParams
    ));
  }

  /**
   * 为当前任务提交结果流目标尺寸与码率预算，不等待服务端生效确认。
   *
   * @param taskId 当前生成任务标识。
   * @param targetSize 可选的生成结果流目标尺寸。
   * @returns 无返回值。
   */
  changeTargetSize(taskId: string, targetSize: ImageSize): void {
    this.send(RoomEvent.changeTargetSize(this.requireUserId(), taskId, targetSize));
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
      const xmaxError: XmaxError = XmaxError.from(error);
      XmaxLogger.error(
        `${XmaxLogger.localized("发送生成停止消息失败 (Failed to Send Generation Stop Message)\n└─ 原因：", "发送生成停止消息失败 (Failed to Send Generation Stop Message)\n└─ Reason: ")}${xmaxError.message}`,
        'Room'
      );
    }
  }

  /**
   * 发送实时生成任务的交互轨迹。
   *
   * @param taskId 生成任务标识。
   * @param points 相对于处理后完整媒体区域的 [0, 1] 轨迹点。
   * @returns 无返回值。
   */
  sendTracks(
    taskId: string,
    points: RealtimePoint[]
  ): void {
    if (taskId.length === 0 || points.length === 0) {
      return;
    }

    this.send(RoomEvent.tracks(
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
    try {
      this.rtcManager.sendRoomMessage(message);
    } catch (error) {
      throw XmaxError.from(error);
    }
    XmaxLogger.debug((): string => this.formatSignalLog(message), 'Room');
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

      return `${XmaxLogger.localized("发送房间信令 (Send Room Signal)\n├─ 类型：", "发送房间信令 (Send Room Signal)\n├─ Type: ")}${eventType}${XmaxLogger.localized("\n└─ 内容：\n   ", "\n└─ Content: \n   ")}${indentedMessage}`;
    } catch (_error) {
      return `${XmaxLogger.localized("发送房间信令 (Send Room Signal)\n└─ 内容：", "发送房间信令 (Send Room Signal)\n└─ Content: ")}${message}`;
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
