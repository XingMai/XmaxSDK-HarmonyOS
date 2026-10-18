//
//  QualityClock.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import systemDateTime from '@ohos.systemDateTime';

/** 调档采样和冷却使用单调时钟，单位秒。 */
export class QualityClock {
  /**
   * 读取自动调档使用的单调时间。
   *
   * @returns 当前单调时间，单位秒。
   */
  static now(): number {
    return systemDateTime.getUptime(systemDateTime.TimeType.ACTIVE, true) / 1000000000;
  }
}
