import { RealtimeContext } from '../../service/realtime/RealtimeContext';
import { RealtimePoint } from '../../service/realtime/RealtimePoint';
import { RealtimeSessionConnection } from '../../service/realtime/RealtimeSessionConnection';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';

/** 定义 RTC 房间生命周期和房间信令发送能力。 */
export interface RoomControlling {

  /**
   * 加入实时房间。
   *
   * @param connection 房间连接信息。
   * @param ensureActive 用于确认当前连接操作仍然有效的回调。
   * @returns 加入房间完成后的 Promise。
   */
  join(
    connection: RealtimeSessionConnection,
    ensureActive: () => void
  ): Promise<void>;

  /**
   * 离开实时房间。
   *
   * @returns 离开房间完成后的 Promise。
   */
  leave(): Promise<void>;

  /**
   * 发送生成开始消息。
   *
   * @param taskId 生成任务标识。
   * @param videoFormat 生成视频格式。
   * @param context 生成上下文。
   * @returns 无返回值。
   */
  startGeneration(
    taskId: string,
    videoFormat: RealtimeVideoFormat,
    context: RealtimeContext
  ): void;

  /**
   * 发送生成条件变更消息。
   *
   * @param taskId 生成任务标识。
   * @param videoFormat 生成视频格式。
   * @param context 新的生成上下文。
   * @returns 无返回值。
   */
  changeGenerationCondition(
    taskId: string,
    videoFormat: RealtimeVideoFormat,
    context: RealtimeContext
  ): void;

  /**
   * 发送生成停止消息。
   *
   * @param taskId 生成任务标识。
   * @returns 无返回值。
   */
  stopGeneration(
    taskId: string
  ): void;

  /**
   * 发送生成任务的交互轨迹。
   *
   * @param taskId 生成任务标识。
   * @param points 模型输入坐标中的轨迹点。
   * @returns 无返回值。
   */
  sendTracks(
    taskId: string,
    points: RealtimePoint[]
  ): void;
}
