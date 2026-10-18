//
//  RtcQualityListener.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { UplinkVideoStatistics, DownlinkVideoStatistics } from './VideoStatistics';

/** 描述 RTC 单个传输方向的网络质量等级。 */
export enum RtcQualityLevel {
  UNKNOWN,
  EXCELLENT,
  GOOD,
  POOR,
  BAD,
  VERY_BAD,
  DOWN
}

/** 接收 RTC 网络质量、视频统计和设备性能告警的内部监听接口。 */
export interface RtcQualityListener {
  /**
   * 接收 RTC 当前上行视频统计，供日志或业务监听使用。
   *
   * @param statistics 当前发布的上行视频统计。
   * @returns 无返回值。
   */
  onUplinkVideoStatistics(statistics: UplinkVideoStatistics): void;

  /**
   * 接收 RTC 指定远端用户的下行视频统计。
   *
   * @param statistics 对应远端用户的下行视频统计。
   * @returns 无返回值。
   */
  onDownlinkVideoStatistics(statistics: DownlinkVideoStatistics): void;

  /**
   * 处理实时网络质量变化。
   *
   * @param uplink 本地上行网络质量等级。
   * @param downlink 本地下行网络质量等级。
   * @returns 无返回值。
   */
  onNetworkQuality(
    uplink: RtcQualityLevel,
    downlink: RtcQualityLevel
  ): void;

  /**
   * 处理实时性能受限或恢复事件。
   *
   * @param limited 是否处于性能受限状态。
   * @param suggestedWidth 建议的视频输入宽度。
   * @param suggestedHeight 建议的视频输入高度。
   * @param suggestedFrameRate 建议的视频输入帧率。
   * @returns 无返回值。
   */
  onPerformanceAlarm(
    limited: boolean,
    suggestedWidth: number,
    suggestedHeight: number,
    suggestedFrameRate: number
  ): void;
}
