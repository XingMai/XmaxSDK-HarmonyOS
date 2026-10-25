//
//  RoomController.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { RealtimeGenerationParameters } from '../../service/realtime/RealtimeGenerationOptions';
import { ImageSize } from '../../service/media/ImageSize';
import { RealtimeTiming } from '../../service/realtime/RealtimeTiming';
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

/** Room event fields used for log formatting. */
interface LoggedRoomEvent {

  // Room signaling event name

  /** The room signaling event name. */
  event?: string;
}

/** Manages RTC room lifecycle, heartbeats, and generation signaling. */
export class RoomController implements RoomControlling {

  // Room transport, heartbeat, and timing dependencies

  /** The adapter for RTC engine, room, and media services. */
  private readonly rtcManager: RtcManaging;

  // Stream components

  /** The room heartbeat scheduler. */
  private readonly heartbeat: RoomHeartbeat;

  /** The shared connection and generation startup timing recorder. */
  private readonly timing: RealtimeTiming;

  // Local room user identity

  /** The current room's local user identifier. */
  private localUserId: string = '';

  /**
   * Creates a room controller.
   *
   * @param rtcManager The RTC manager for room connections and messaging.
   * @param timing The startup timing recorder shared with the realtime manager.
   */
  constructor(
    rtcManager: RtcManaging,
    timing: RealtimeTiming = new RealtimeTiming()
  ) {
    this.timing = timing;
    this.rtcManager = rtcManager;
    this.heartbeat = new RoomHeartbeat(rtcManager);
  }

  /**
   * Joins the RTC room and starts room heartbeats.
   *
   * The Promise fulfills after joining the room.
   *
   * @param connection The room connection information.
   * @param ensureActive The callback checking connection operation validity.
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
   * Stops heartbeats and leaves the RTC room.
   *
   * The Promise fulfills after leaving the room.
   */
  async leave(): Promise<void> {
    this.heartbeat.stop();
    this.localUserId = '';

    await this.rtcManager.leaveRoom();
  }

  /**
   * Sends the generation start signal.
   *
   * @param taskId The generation task identifier.
   * @param videoFormat The generation video format.
   * @param context The realtime generation conditions.
   * @param faceRestoration Whether to enable face restoration.
   * @param targetSize The optional result stream target dimensions.
   * @param paddingContain Whether to preserve media aspect ratio with server-side padding.
   * @param extraParams The static generation parameters passed internally by the SDK.
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
   * Sends updated realtime generation conditions.
   *
   * @param taskId The generation task identifier.
   * @param videoFormat The generation video format.
   * @param context The new realtime generation conditions.
   * @param faceRestoration Whether to enable face restoration.
   * @param targetSize The optional result stream target dimensions.
   * @param paddingContain Whether to preserve media aspect ratio with server-side padding.
   * @param extraParams The static generation parameters passed internally by the SDK.
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
   * Submits task result dimensions and bitrate without waiting for server application.
   *
   * @param taskId The current generation task identifier.
   * @param targetSize The optional result stream target dimensions.
   */
  changeTargetSize(
    taskId: string,
    targetSize: ImageSize
  ): void {
    this.send(RoomEvent.changeTargetSize(
      this.requireUserId(),
      taskId,
      targetSize
    ));
  }

  /**
   * Attempts to send the generation stop signal.
   *
   * @param taskId The generation task identifier.
   */
  stopGeneration(
    taskId: string
  ): void {
    if (taskId.length === 0 || this.localUserId.length === 0) {
      return;
    }

    try {
      this.send(RoomEvent.stop(
        this.localUserId,
        taskId
      ));
    } catch (error) {
      const xmaxError: XmaxError = XmaxError.from(error);
      XmaxLogger.error(
        `${XmaxLogger.localized("发送生成停止消息失败 (Failed to Send Generation Stop Message)\n└─ 原因：", "发送生成停止消息失败 (Failed to Send Generation Stop Message)\n└─ Reason: ")}${xmaxError.message}`,
        'Room'
      );
    }
  }

  /**
   * Sends interaction trajectories to a realtime generation task.
   *
   * @param taskId The generation task identifier.
   * @param points The trajectory points normalized to the complete processed media in [0, 1].
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
   * Sends room signaling with structured logs.
   *
   * @param message The serialized room signal.
   */
  private send(
    message: string
  ): void {
    try {
      this.rtcManager.sendRoomMessage(message);
    } catch (error) {
      throw XmaxError.from(error);
    }
    XmaxLogger.debug(
      (): string => this.formatSignalLog(message),
      'Room'
    );
  }

  /**
   * Formats room signaling for readable logs.
   *
   * @param message The serialized room signal.
   *
   * @returns The formatted log text.
   */
  private formatSignalLog(
    message: string
  ): string {
    try {
      const event = JSON.parse(message) as LoggedRoomEvent;
      const eventType: string = event.event ?? 'unknown';
      const formattedMessage: string = JSON.stringify(
        event,
        null,
        2
      );
      const indentedMessage: string = formattedMessage.replace(
        /\n/g,
        '\n   '
      );

      return `${XmaxLogger.localized("发送房间信令 (Send Room Signal)\n├─ 类型：", "发送房间信令 (Send Room Signal)\n├─ Type: ")}${eventType}${XmaxLogger.localized("\n└─ 内容：\n   ", "\n└─ Content: \n   ")}${indentedMessage}`;
    } catch (_error) {
      return `${XmaxLogger.localized("发送房间信令 (Send Room Signal)\n└─ 内容：", "发送房间信令 (Send Room Signal)\n└─ Content: ")}${message}`;
    }
  }

  /**
   * Returns the local user identifier for the current room.
   *
   * @returns The current local user identifier.
   */
  private requireUserId(): string {
    if (this.localUserId.length === 0) {
      throw new XmaxError(
        XmaxErrorCode.RTC_ERROR,
        'RTC room is not joined'
      );
    }
    return this.localUserId;
  }
}
