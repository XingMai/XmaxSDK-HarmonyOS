//
//  InteractionPoint.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/** 记录视口坐标系内的单个交互点。 */
export class InteractionPoint {

  /** 视口内触点坐标 */
  readonly x: number;
  readonly y: number;

  /**
   * 创建视口交互点。
   *
   * @param x 横坐标。
   * @param y 纵坐标。
   * @returns 新建的 InteractionPoint 实例。
   */
  constructor(
    x: number,
    y: number
  ) {
    this.x = x;
    this.y = y;
  }
}
