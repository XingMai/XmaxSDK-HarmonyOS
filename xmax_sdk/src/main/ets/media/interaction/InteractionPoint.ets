//
//  InteractionPoint.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/** A touch point in viewport coordinates. */
export class InteractionPoint {

  /** The horizontal coordinate. */
  readonly x: number;

  /** The vertical coordinate. */
  readonly y: number;

  /** Creates a viewport touch point. */
  constructor(
    x: number,
    y: number
  ) {
    this.x = x;
    this.y = y;
  }
}
