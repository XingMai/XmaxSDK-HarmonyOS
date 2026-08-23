import { TrajectoryId } from './TrajectoryId';
import { TrajectoryPoint } from './TrajectoryPoint';

export interface TrajectoryEffectRendering {
  /** 动态效果刷新间隔，单位为毫秒。 */
  readonly tickIntervalMs: number;

  /** 轨迹画布上下文。 */
  readonly trailContext: CanvasRenderingContext2D;

  /** 动态效果画布上下文。 */
  readonly effectContext: CanvasRenderingContext2D;

  /**
   * 更新渲染区域尺寸。
   *
   * @param width 渲染区域宽度。
   * @param height 渲染区域高度。
   */
  resize(
    width: number,
    height: number
  ): void;

  /**
   * 渲染轨迹起点。
   *
   * @param points 新开始的轨迹点。
   */
  renderBegan(
    points: TrajectoryPoint[]
  ): void;

  /**
   * 渲染移动中的轨迹点。
   *
   * @param points 发生移动的轨迹点。
   */
  renderMoved(
    points: TrajectoryPoint[]
  ): void;

  /**
   * 结束指定轨迹。
   *
   * @param identifiers 已结束的轨迹标识。
   */
  renderEnded(
    identifiers: TrajectoryId[]
  ): void;

  /**
   * 推进一帧动态轨迹效果。
   *
   * @param timestamp 当前时间戳，单位为毫秒。
   */
  tick(timestamp: number): void;

  /**
   * 判断是否仍有需要持续刷新的轨迹效果。
   *
   * @returns 存在活动轨迹或渐隐效果时返回 true。
   */
  isAnimating(): boolean;

  /** 清理全部轨迹效果。 */
  reset(): void;
}
