import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import { RealtimePoint } from '../../service/realtime/RealtimePoint';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import { InteractionControlling } from './InteractionControlling';
import { InteractionCoordinateMapper } from './InteractionCoordinateMapper';
import { InteractionFrame } from './InteractionFrame';
import { InteractionPoint } from './InteractionPoint';

type InteractionSender = (
  taskId: string,
  points: RealtimePoint[]
) => void;

/** 保存当前生成任务的交互坐标映射上下文。 */
class ActiveInteraction {

  readonly taskId: string;
  readonly videoFormat: RealtimeVideoFormat;

  /**
   * 创建交互上下文。
   *
   * @param taskId 生成任务标识。
   * @param videoFormat 模型输入视频格式。
   */
  constructor(
    taskId: string,
    videoFormat: RealtimeVideoFormat
  ) {
    this.taskId = taskId;
    this.videoFormat = videoFormat;
  }
}

/** 将渲染容器中的交互行为转换为模型输入坐标并发送。 */
export class InteractionController implements InteractionControlling {

  // 交互发送器
  private readonly sender: InteractionSender;

  // 交互资源
  private activeInteraction: ActiveInteraction | null = null;

  /**
   * 创建交互采集 Controller。
   *
   * @param sender 交互轨迹发送方法。
   */
  constructor(sender: InteractionSender) {
    // 交互发送器
    this.sender = sender;
  }

  /**
   * 开始处理指定生成任务的交互输入。
   *
   * @param taskId 生成任务标识。
   * @param videoFormat 模型输入视频格式。
   * @returns 无返回值。
   */
  start(
    taskId: string,
    videoFormat: RealtimeVideoFormat
  ): void {
    this.activeInteraction = new ActiveInteraction(taskId, videoFormat);
  }

  /**
   * 停止处理当前生成任务的交互输入。
   *
   * @returns 无返回值。
   */
  stop(): void {
    this.activeInteraction = null;
  }

  /**
   * 转换并发送一帧交互轨迹。
   *
   * @param frame 当前容器中的交互点和显示信息。
   * @returns 无返回值。
   */
  submit(frame: InteractionFrame): void {
    const interaction: ActiveInteraction | null = this.activeInteraction;
    if (interaction === null || frame.points.length === 0) {
      return;
    }

    const points: RealtimePoint[] = [];
    frame.points.forEach((point: InteractionPoint): void => {
      const mappedPoint: RealtimePoint | null = InteractionCoordinateMapper.map(
        point,
        frame.viewportWidth,
        frame.viewportHeight,
        interaction.videoFormat,
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
        `发送交互轨迹失败\n└─ 原因：${reason}`,
        'Interaction'
      );
    }
  }
}
