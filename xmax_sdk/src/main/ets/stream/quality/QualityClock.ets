//
//  QualityClock.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import systemDateTime from '@ohos.systemDateTime';

/** Adaptive sampling and cooldown use a monotonic clock, in seconds. */
export class QualityClock {

  /**
   * Returns monotonic adaptive quality time.
   *
   * @returns The current monotonic time, in seconds.
   */
  static now(): number {
    return systemDateTime.getUptime(
      systemDateTime.TimeType.ACTIVE,
      true
    ) / 1000000000;
  }
}
