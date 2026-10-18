//
//  RealtimePoint.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/** 相对于处理后完整媒体区域的 [0, 1] 坐标；左上角为 (0, 0)，右下角为 (1, 1)。 */
export class RealtimePoint {

  /** 归一化媒体坐标 */
  readonly x: number;
  readonly y: number;

  /**
   * 创建归一化交互点。
   *
   * @param x 横坐标。
   * @param y 纵坐标。
   * @returns 新建的 RealtimePoint 实例。
   */
  constructor(
    x: number,
    y: number
  ) {
    this.x = x;
    this.y = y;
  }
}
