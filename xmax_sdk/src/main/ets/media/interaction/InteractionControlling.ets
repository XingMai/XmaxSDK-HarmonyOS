import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import { InteractionFrame } from './InteractionFrame';

/** 定义生成任务的交互输入处理能力。 */
export interface InteractionControlling {

  /**
   * 开始处理生成任务的交互输入。
   *
   * @param taskId 生成任务标识。
   * @param videoFormat 模型输入视频格式。
   * @returns 无返回值。
   */
  start(
    taskId: string,
    videoFormat: RealtimeVideoFormat
  ): void;

  /**
   * 停止处理交互输入。
   *
   * @returns 无返回值。
   */
  stop(): void;

  /**
   * 提交一帧交互输入。
   *
   * @param frame 当前容器中的交互点和显示信息。
   * @returns 无返回值。
   */
  submit(
    frame: InteractionFrame
  ): void;
}
