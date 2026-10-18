//
//  TrajectoryEffectRendering.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { TrajectoryId } from './TrajectoryId';
import { TrajectoryPoint } from './TrajectoryPoint';

/** 自定义轨迹效果的绘制接口，由轨迹视图驱动触摸事件和动画更新。 */
export interface TrajectoryEffectRendering {

  /** 动画刷新节奏 */
  /** 动态效果刷新间隔，单位为毫秒。 */
  readonly tickIntervalMs: number;

  /** 轨迹与动态效果画布 */
  /** 轨迹画布上下文。 */
  readonly trailContext: CanvasRenderingContext2D;

  /** 动态效果画布上下文。 */
  readonly effectContext: CanvasRenderingContext2D;

  /**
   * 更新渲染区域尺寸。
   *
   * @param width 渲染区域宽度。
   * @param height 渲染区域高度。
   * @returns 无返回值。
   */
  resize(
    width: number,
    height: number
  ): void;

  /**
   * 渲染轨迹起点。
   *
   * @param points 新开始的轨迹点。
   * @returns 无返回值。
   */
  renderBegan(
    points: TrajectoryPoint[]
  ): void;

  /**
   * 渲染移动中的轨迹点。
   *
   * @param points 发生移动的轨迹点。
   * @returns 无返回值。
   */
  renderMoved(
    points: TrajectoryPoint[]
  ): void;

  /**
   * 结束指定轨迹。
   *
   * @param identifiers 已结束的轨迹标识。
   * @returns 无返回值。
   */
  renderEnded(
    identifiers: TrajectoryId[]
  ): void;

  /**
   * 推进一帧动态轨迹效果。
   *
   * @param timestamp 当前时间戳，单位为毫秒。
   * @returns 无返回值。
   */
  tick(timestamp: number): void;

  /**
   * 判断是否仍有需要持续刷新的轨迹效果。
   *
   * @returns 仍有活动触点或残留轨迹需要消退时返回 true。
   */
  isAnimating(): boolean;

  /**
   * 清理全部轨迹效果。
   *
   * @returns 无返回值。
   */
  reset(): void;
}
