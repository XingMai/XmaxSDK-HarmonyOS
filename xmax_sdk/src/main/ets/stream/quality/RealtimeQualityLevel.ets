//
//  RealtimeQualityLevel.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/**
 * A transmission quality level, from highest quality at L1 to lowest bandwidth at L5.
 * Quality levels are independent of network quality ratings. Dimensions remain subject to
 * alignment, minimum input area, and minimum short-edge constraints.
 */
export enum RealtimeQualityLevel {

  /** Retains the local media baseline dimensions. */
  L1 = 1,

  /** Targets 90% of the baseline width and height. */
  L2 = 2,

  /** Targets 75% of the baseline width and height. */
  L3 = 3,

  /** Targets 60% of the baseline width and height. */
  L4 = 4,

  /** Targets 50% of the baseline width and height. */
  L5 = 5
}
