//
//  TrajectoryId.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/** 在一次触摸序列中唯一标识一条轨迹。 */
export class TrajectoryId {

  /** 轨迹身份 */
  readonly rawValue: number;

  /**
   * 创建轨迹标识。
   *
   * @param rawValue 轨迹标识的原始数值。
   * @returns 新建的 TrajectoryId 实例。
   */
  constructor(rawValue: number) {
    this.rawValue = rawValue;
  }
}
