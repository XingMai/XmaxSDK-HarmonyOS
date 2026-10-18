import { TrajectoryId } from './TrajectoryId';

export class TrajectoryPoint {
  readonly id: TrajectoryId;
  readonly x: number;
  readonly y: number;
  /** 相对于处理后完整媒体区域的归一化坐标，包含 Fit/Fill 的留白或裁剪偏移。 */
  readonly normalizedX: number;
  readonly normalizedY: number;
  readonly timestamp: number;

  constructor(
    id: TrajectoryId,
    x: number,
    y: number,
    normalizedX: number,
    normalizedY: number,
    timestamp: number
  ) {
    this.id = id;
    this.x = x;
    this.y = y;
    this.normalizedX = normalizedX;
    this.normalizedY = normalizedY;
    this.timestamp = timestamp;
  }
}
