//
//  InteractionController.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { ImageSize } from '../../service/media/ImageSize';
import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import { RealtimePoint } from '../../service/realtime/RealtimePoint';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import { InteractionControlling } from './InteractionControlling';
import { InteractionCoordinateMapper } from './InteractionCoordinateMapper';
import { InteractionFrame } from './InteractionFrame';
import { InteractionPoint } from './InteractionPoint';

/**
 * Sends normalized interaction points to the active task.
 *
 * @param taskId The current generation task identifier.
 * @param points The touch points to submit or draw.
 */
type InteractionSender = (
  taskId: string,
  points: RealtimePoint[]
) => void;

/** The coordinate mapping context for the active generation task. */
class ActiveInteraction {

  /** The generation task identifier. */
  readonly taskId: string;

  /** The fixed processed-media dimensions used for interaction mapping. */
  readonly resolvedMediaSize: ImageSize;

  /**
   * Creates an interaction context.
   *
   * @param taskId The generation task identifier.
   * @param videoFormat The processed local media format serving as the fixed normalized coordinate
   * baseline.
   */
  constructor(
    taskId: string,
    videoFormat: RealtimeVideoFormat
  ) {
    this.taskId = taskId;
    this.resolvedMediaSize = new ImageSize(
      videoFormat.width,
      videoFormat.height
    );
  }
}

/** Maps viewport interactions into normalized processed-media coordinates and sends them. */
export class InteractionController implements InteractionControlling {

  /** The function sending normalized interaction points. */
  private readonly sender: InteractionSender;

  /** The confirmed task and fixed interaction coordinate baseline. */
  private activeInteraction: ActiveInteraction | null = null;

  /** Creates an interaction controller. */
  constructor(
    sender: InteractionSender
  ) {
    // Interaction sender
    this.sender = sender;
  }

  /**
   * Starts interaction processing for a generation task.
   *
   * @param taskId The generation task identifier.
   * @param videoFormat The processed local media format serving as the fixed normalized coordinate
   * baseline.
   */
  start(
    taskId: string,
    videoFormat: RealtimeVideoFormat
  ): void {
    this.activeInteraction = new ActiveInteraction(
      taskId,
      videoFormat
    );
  }

  /** Stops interaction processing for the active task. */
  stop(): void {
    this.activeInteraction = null;
  }

  /**
   * Submits trajectories, discarding them without a confirmed task while preserving local drawing.
   *
   * @param frame The current viewport touch points and display information.
   */
  submit(
    frame: InteractionFrame
  ): void {
    if (frame.points.length === 0 || this.activeInteraction === null) {
      return;
    }
    this.send(frame);
  }

  /**
   * Maps and sends points using the active task's media aspect ratio.
   *
   * @param frame The touch points and viewport display information.
   */
  private send(
    frame: InteractionFrame
  ): void {
    const interaction: ActiveInteraction | null = this.activeInteraction;
    if (interaction === null) {
      return;
    }
    const points: RealtimePoint[] = [];
    frame.points.forEach((point: InteractionPoint): void => {
      const mappedPoint: RealtimePoint | null = InteractionCoordinateMapper.map(
        point,
        frame.viewportWidth,
        frame.viewportHeight,
        interaction.resolvedMediaSize,
        frame.contentMode
      );
      if (mappedPoint !== null) {
        points.push(mappedPoint);
      }
    });
    if (points.length === 0) {
      return;
    }

    try {
      this.sender(
        interaction.taskId,
        points
      );
    } catch (error) {
      const reason: string = error instanceof Error ? error.message : String(error);
      XmaxLogger.error(
        `${XmaxLogger.localized("发送交互轨迹失败 (Failed to Send Interaction Trajectory)\n└─ 原因：", "发送交互轨迹失败 (Failed to Send Interaction Trajectory)\n└─ Reason: ")}${reason}`,
        'Interaction'
      );
    }
  }
}
