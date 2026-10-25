//
//  XmaxLoggerOption.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/** SDK log categories that can be combined with bitwise OR. */
export enum XmaxLoggerOption {

  /** Disables all SDK logs by default. */
  NONE = 0,

  /** API, room, realtime, storage, and other operational logs. */
  BUSINESS = 1 << 0,

  /** Startup timing, RTC media statistics, network quality, and performance alarm logs. */
  PERFORMANCE = 1 << 1,

  /** Enables all SDK logs. */
  ALL = BUSINESS | PERFORMANCE
}
