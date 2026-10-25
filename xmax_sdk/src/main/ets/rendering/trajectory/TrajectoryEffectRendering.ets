//
//  TrajectoryEffectRendering.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { TrajectoryId } from './TrajectoryId';
import { TrajectoryPoint } from './TrajectoryPoint';

/** An interface for custom trajectory effects driven by touch and animation events. */
export interface TrajectoryEffectRendering {

  /** The animation refresh interval, in milliseconds. */
  readonly tickIntervalMs: number;

  /** The trajectory drawing context. */
  readonly trailContext: CanvasRenderingContext2D;

  /** The animated effect drawing context. */
  readonly effectContext: CanvasRenderingContext2D;

  /**
   * Updates rendering area dimensions.
   *
   * @param width The rendering area width.
   * @param height The rendering area height.
   */
  resize(
    width: number,
    height: number
  ): void;

  /**
   * Renders new trajectory points.
   *
   * @param points The starting trajectory points.
   */
  renderBegan(
    points: TrajectoryPoint[]
  ): void;

  /**
   * Renders moving trajectory points.
   *
   * @param points The moved trajectory points.
   */
  renderMoved(
    points: TrajectoryPoint[]
  ): void;

  /**
   * Ends the specified trajectories.
   *
   * @param identifiers The completed trajectory identifiers.
   */
  renderEnded(
    identifiers: TrajectoryId[]
  ): void;

  /**
   * Advances one animation frame.
   *
   * @param timestamp The current timestamp, in milliseconds.
   */
  tick(
    timestamp: number
  ): void;

  /**
   * Returns whether trajectory effects need continued refreshing.
   *
   * @returns True while active touches or residual trajectories need animation.
   */
  isAnimating(): boolean;

  /** Clears all trajectory effects. */
  reset(): void;
}
