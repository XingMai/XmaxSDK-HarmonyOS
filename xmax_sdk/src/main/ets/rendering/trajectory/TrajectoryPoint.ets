import { TrajectoryId } from './TrajectoryId';

export class TrajectoryPoint {
  readonly id: TrajectoryId;
  readonly x: number;
  readonly y: number;
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
