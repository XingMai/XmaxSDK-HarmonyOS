/** 相对于处理后完整媒体区域的 [0, 1] 坐标；左上角为 (0, 0)，右下角为 (1, 1)。 */
export class RealtimePoint {
  readonly x: number;
  readonly y: number;

  constructor(
    x: number,
    y: number
  ) {
    this.x = x;
    this.y = y;
  }
}
