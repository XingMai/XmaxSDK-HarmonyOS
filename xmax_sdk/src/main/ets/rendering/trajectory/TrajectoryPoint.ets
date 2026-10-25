//
//  TrajectoryPoint.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { TrajectoryId } from './TrajectoryId';

/** A trajectory sample with viewport coordinates, normalized coordinates, and time. */
export class TrajectoryPoint {

  /** The trajectory identifier. */
  readonly id: TrajectoryId;

  /** The horizontal coordinate. */
  readonly x: number;

  /** The vertical coordinate. */
  readonly y: number;

  /**
   * Coordinates normalized to the complete processed media, accounting for FIT padding or FILL
   * cropping.
   */
  readonly normalizedX: number;

  /** The media-normalized vertical coordinate in 0 to 1. */
  readonly normalizedY: number;

  /** The trajectory sample timestamp, in milliseconds. */
  readonly timestamp: number;

  /** Creates a trajectory sample. */
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
