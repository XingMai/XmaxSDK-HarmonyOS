//
//  RtcQualityListener.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { UplinkVideoStatistics, DownlinkVideoStatistics } from './VideoStatistics';

/** The network quality level for one RTC direction. */
export enum RtcQualityLevel {

  /** Network quality is unavailable. */
  UNKNOWN,

  /** Excellent network quality. */
  EXCELLENT,

  /** Good network quality. */
  GOOD,

  /** Poor network quality. */
  POOR,

  /** Bad network quality. */
  BAD,

  /** Very bad network quality. */
  VERY_BAD,

  /** The network is disconnected. */
  DOWN
}

/** An internal listener for RTC quality, video statistics, and device performance alarms. */
export interface RtcQualityListener {

  /**
   * Receives current uplink statistics for logs or application listeners.
   *
   * @param statistics The published uplink video statistics.
   */
  onUplinkVideoStatistics(
    statistics: UplinkVideoStatistics
  ): void;

  /**
   * Receives a remote user's downlink video statistics.
   *
   * @param statistics The remote user's downlink video statistics.
   */
  onDownlinkVideoStatistics(
    statistics: DownlinkVideoStatistics
  ): void;

  /**
   * Handles network quality changes.
   *
   * @param uplink The local uplink quality level.
   * @param downlink The local downlink quality level.
   */
  onNetworkQuality(
    uplink: RtcQualityLevel,
    downlink: RtcQualityLevel
  ): void;

  /**
   * Handles device performance limitation and recovery.
   *
   * @param limited Whether device performance is limited.
   * @param suggestedWidth The recommended input width.
   * @param suggestedHeight The recommended input height.
   * @param suggestedFrameRate The recommended input frame rate.
   */
  onPerformanceAlarm(
    limited: boolean,
    suggestedWidth: number,
    suggestedHeight: number,
    suggestedFrameRate: number
  ): void;
}
