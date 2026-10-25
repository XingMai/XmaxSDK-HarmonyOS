//
//  RealtimePoint.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/**
 * A point normalized to the complete processed media: (0, 0) at top left and (1, 1) at bottom
 * right.
 */
export class RealtimePoint {

  /** The horizontal coordinate. */
  readonly x: number;

  /** The vertical coordinate. */
  readonly y: number;

  /** Creates a normalized interaction point. */
  constructor(
    x: number,
    y: number
  ) {
    this.x = x;
    this.y = y;
  }
}
