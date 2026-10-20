//
//  InteractionController.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
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

const MAX_PENDING_FRAMES: number = 64;
const REPLAY_INTERVAL_MS: number = 30;

/**
 * 向当前生成任务发送归一化交互点的回调。
 *
 * @param taskId 当前生成任务标识。
 * @param points 本次提交或绘制的触点集合。
 * @returns 无返回值。
 */
type InteractionSender = (
  taskId: string,
  points: RealtimePoint[]
) => void;

/** 保存当前生成任务的交互坐标映射上下文。 */
class ActiveInteraction {

  /** 当前任务与固定媒体坐标基准 */
  readonly taskId: string;
  readonly resolvedMediaSize: ImageSize;

  /**
   * 创建交互上下文。
   *
   * @param taskId 生成任务标识。
   * @param videoFormat 处理后的本地媒体格式，作为固定归一化坐标基准。
   * @returns 新建的 ActiveInteraction 实例。
   */
  constructor(
    taskId: string,
    videoFormat: RealtimeVideoFormat
  ) {
    this.taskId = taskId;
    this.resolvedMediaSize = new ImageSize(videoFormat.width, videoFormat.height);
  }
}

/** 将渲染容器中的交互行为转换为处理后媒体的 [0, 1] 坐标并发送。 */
export class InteractionController implements InteractionControlling {

  /** 交互信令发送依赖 */
  private readonly sender: InteractionSender;

  /** 活动交互任务 */
  private activeInteraction: ActiveInteraction | null = null;

  /** 任务确认前的有限轨迹缓存与顺序回放 */
  private readonly pendingFrames: InteractionFrame[] = [];
  private replayTimer: number = -1;

  /**
   * 创建交互采集 Controller。
   *
   * @param sender 交互轨迹发送方法。
   * @returns 新建的 InteractionController 实例。
   */
  constructor(sender: InteractionSender) {
    // 交互发送器
    this.sender = sender;
  }

  /**
   * 开始处理指定生成任务的交互输入。
   *
   * @param taskId 生成任务标识。
   * @param videoFormat 处理后的本地媒体格式，作为固定归一化坐标基准。
   * @returns 无返回值。
   */
  start(
    taskId: string,
    videoFormat: RealtimeVideoFormat
  ): void {
    this.activeInteraction = new ActiveInteraction(taskId, videoFormat);
    if (this.replayTimer < 0) {
      this.replayPending();
    }
  }

  /**
   * 停止处理当前生成任务的交互输入。
   *
   * @returns 无返回值。
   */
  stop(): void {
    this.activeInteraction = null;
    this.pendingFrames.length = 0;
    if (this.replayTimer >= 0) {
      clearTimeout(this.replayTimer);
      this.replayTimer = -1;
    }
  }

  /**
   * 提交交互轨迹；任务确认前暂存最近 64 帧，确认后按采样间隔顺序发送。
   *
   * @param frame 当前容器中的交互点和显示信息。
   * @returns 无返回值。
   */
  submit(frame: InteractionFrame): void {
    if (frame.points.length === 0) {
      return;
    }
    if (this.activeInteraction === null || this.replayTimer >= 0) {
      this.pendingFrames.push(new InteractionFrame(frame.points.map((point: InteractionPoint): InteractionPoint =>
        new InteractionPoint(point.x, point.y)), frame.viewportWidth, frame.viewportHeight, frame.contentMode));
      if (this.pendingFrames.length > MAX_PENDING_FRAMES) {
        this.pendingFrames.shift();
      }
      return;
    }
    this.send(frame);
  }

  /**
   * 按采样间隔发送已缓存的触点，停止任务时取消剩余回放。
   *
   * @returns 无返回值。
   */
  private replayPending(): void {
    this.replayTimer = -1;
    if (this.activeInteraction === null) {
      return;
    }
    const frame: InteractionFrame | undefined = this.pendingFrames.shift();
    if (frame === undefined) {
      return;
    }
    this.send(frame);
    this.replayTimer = setTimeout((): void => this.replayPending(), REPLAY_INTERVAL_MS);
  }

  /**
   * 按当前任务的媒体比例转换并发送触点。
   *
   * @param frame 交互点和对应的视口显示信息。
   * @returns 无返回值。
   */
  private send(frame: InteractionFrame): void {
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
      this.sender(interaction.taskId, points);
    } catch (error) {
      const reason: string = error instanceof Error ? error.message : String(error);
      XmaxLogger.error(
        `${XmaxLogger.localized("发送交互轨迹失败 (Failed to Send Interaction Trajectory)\n└─ 原因：", "发送交互轨迹失败 (Failed to Send Interaction Trajectory)\n└─ Reason: ")}${reason}`,
        'Interaction'
      );
    }
  }
}
