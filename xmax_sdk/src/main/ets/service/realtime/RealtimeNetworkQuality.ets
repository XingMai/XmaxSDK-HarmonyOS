//
//  RealtimeNetworkQuality.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/** 描述上行或下行网络的可用质量等级。 */
export enum RealtimeNetworkQualityLevel {
  UNKNOWN = 'Unknown',
  EXCELLENT = 'Excellent',
  GOOD = 'Good',
  POOR = 'Poor',
  BAD = 'Bad',
  VERY_BAD = 'VeryBad',
  DOWN = 'Down'
}

/** 同时提供本地上行和下行的网络质量等级。 */
export class RealtimeNetworkQuality {

  /** 上下行网络质量 */
  readonly uplink: RealtimeNetworkQualityLevel;
  readonly downlink: RealtimeNetworkQualityLevel;

  /**
   * 创建上下行网络质量快照。
   *
   * @param uplink 本地上行网络等级或建议档位。
   * @param downlink 本地下行的网络质量等级或建议档位。
   * @returns 新建的 RealtimeNetworkQuality 实例。
   */
  constructor(
    uplink: RealtimeNetworkQualityLevel,
    downlink: RealtimeNetworkQualityLevel
  ) {
    this.uplink = uplink;
    this.downlink = downlink;
  }
}

/**
 * 接收上下行网络质量变化的回调。
 *
 * @param quality 当前方向或上下行的网络质量采样。
 * @returns 无返回值。
 */
export type RealtimeNetworkQualityListener = (quality: RealtimeNetworkQuality) => void;
