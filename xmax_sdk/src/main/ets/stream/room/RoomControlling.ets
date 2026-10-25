//
//  RoomControlling.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { RealtimeGenerationParameters } from '../../service/realtime/RealtimeGenerationOptions';
import { ImageSize } from '../../service/media/ImageSize';
import { RealtimeContext } from '../../service/realtime/RealtimeContext';
import { RealtimePoint } from '../../service/realtime/RealtimePoint';
import { RealtimeSessionConnection } from '../../service/realtime/RealtimeSessionConnection';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';

/** An interface for RTC room lifecycle and signaling. */
export interface RoomControlling {

  /**
   * Updates return format and bitrate without changing the generation canvas.
   *
   * @param taskId The current generation task identifier.
   * @param targetSize The optional result stream target dimensions.
   */
  changeTargetSize(
    taskId: string,
    targetSize: ImageSize
  ): void;

  /**
   * Joins the realtime room.
   *
   * The Promise fulfills after joining the room.
   *
   * @param connection The room connection information.
   * @param ensureActive The callback checking connection operation validity.
   */
  join(
    connection: RealtimeSessionConnection,
    ensureActive: () => void
  ): Promise<void>;

  /**
   * Leaves the realtime room.
   *
   * The Promise fulfills after leaving the room.
   */
  leave(): Promise<void>;

  /**
   * Sends a generation start message.
   *
   * @param taskId The generation task identifier.
   * @param videoFormat The generation video format.
   * @param context The generation conditions.
   * @param faceRestoration Whether to enable face restoration.
   * @param targetSize The optional result stream target dimensions.
   * @param paddingContain Whether to preserve media aspect ratio with server-side padding.
   * @param extraParams The static generation parameters passed internally by the SDK.
   */
  startGeneration(
    taskId: string,
    videoFormat: RealtimeVideoFormat,
    context: RealtimeContext,
    faceRestoration?: boolean,
    targetSize?: ImageSize,
    paddingContain?: boolean,
    extraParams?: RealtimeGenerationParameters
  ): void;

  /**
   * Sends a generation condition update.
   *
   * @param taskId The generation task identifier.
   * @param videoFormat The generation video format.
   * @param context The new generation conditions.
   * @param faceRestoration Whether to enable face restoration.
   * @param targetSize The optional result stream target dimensions.
   * @param paddingContain Whether to preserve media aspect ratio with server-side padding.
   * @param extraParams The static generation parameters passed internally by the SDK.
   */
  changeGenerationCondition(
    taskId: string,
    videoFormat: RealtimeVideoFormat,
    context: RealtimeContext,
    faceRestoration?: boolean,
    targetSize?: ImageSize,
    paddingContain?: boolean,
    extraParams?: RealtimeGenerationParameters
  ): void;

  /**
   * Sends a generation stop message.
   *
   * @param taskId The generation task identifier.
   */
  stopGeneration(
    taskId: string
  ): void;

  /**
   * Sends interaction trajectories to a generation task.
   *
   * @param taskId The generation task identifier.
   * @param points The trajectory points normalized to the complete processed media in [0, 1].
   */
  sendTracks(
    taskId: string,
    points: RealtimePoint[]
  ): void;
}
