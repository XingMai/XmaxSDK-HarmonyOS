//
//  TrajectoryId.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/** A trajectory identity unique within one touch sequence. */
export class TrajectoryId {

  /** The numeric trajectory identity. */
  readonly rawValue: number;

  /** Creates a trajectory identifier. */
  constructor(
    rawValue: number
  ) {
    this.rawValue = rawValue;
  }
}
