//
//  VolcRtcStatsLogger.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import {
  NetworkQuality,
  NetworkQualityStats,
  PerformanceAlarmReason,
  SourceWantedData
} from '@bytertc/volcenginertc';
import { XmaxLogger } from '../logging/XmaxLogger';
import { XmaxLoggerOption } from '../logging/XmaxLoggerOption';

const VOLC_LOG_CATEGORY: string = 'RTC';

/** VolcEngine network and performance diagnostics. RtcStatsLogger formats public video metrics. */
export class VolcRtcStatsLogger {

  /**
   * Logs native RTC bandwidth, packet loss, and round-trip latency.
   *
   * @param localQuality The local RTC network quality statistics.
   * @param remoteQualities The remote users' RTC network quality statistics.
   */
  static logNetworkQuality(
    localQuality: NetworkQualityStats,
    remoteQualities: NetworkQualityStats[]
  ): void {
    if (!XmaxLogger.isEnabled(XmaxLoggerOption.PERFORMANCE)) {
      return;
    }
    const hasRemoteQuality: boolean = remoteQualities.length > 0;
    const localBranch: string = hasRemoteQuality ? '├─' : '└─';
    const localIndent: string = hasRemoteQuality ? '│  ' : '   ';
    const localQualityText: string = VolcRtcStatsLogger.networkQualityName(
      localQuality.tx_quality
    );
    const localMetricsText: string = VolcRtcStatsLogger.formatNetworkMetrics(
      localQuality,
      true
    );
    const lines: string[] = [
      "网络质量 (Network Quality)",
      `${localBranch}${XmaxLogger.localized(" 本地发送（上行）", " Local Send (Uplink)")}`,
      `${localIndent}${XmaxLogger.localized("├─ 质量：", "├─ Quality: ")}${localQualityText}`,
      `${localIndent}└─ ${localMetricsText}`
    ];

    remoteQualities.forEach((quality: NetworkQualityStats, index: number): void => {
      const isLast: boolean = index === remoteQualities.length - 1;
      const branch: string = isLast ? '└─' : '├─';
      const indent: string = isLast ? '   ' : '│  ';
      const qualityText: string = VolcRtcStatsLogger.networkQualityName(quality.rx_quality);
      const metricsText: string = VolcRtcStatsLogger.formatNetworkMetrics(
        quality,
        false
      );

      lines.push(`${branch}${XmaxLogger.localized(" 远端接收 ", " Remote Receive ")}${quality.uid}${XmaxLogger.localized("（下行）", " (Downlink)")}`);
      lines.push(`${indent}${XmaxLogger.localized("├─ 质量：", "├─ Quality: ")}${qualityText}`);
      lines.push(`${indent}└─ ${metricsText}`);
    });

    XmaxLogger.debug(
      lines.join('\n'),
      VOLC_LOG_CATEGORY,
      XmaxLoggerOption.PERFORMANCE
    );
  }

  /**
   * Logs native RTC performance alarms and recommended formats.
   *
   * @param reason The termination reason or platform alarm reason.
   * @param data The capture dimensions and frame rate recommended by the RTC performance alarm.
   */
  static logPerformanceAlarm(
    reason: PerformanceAlarmReason,
    data: SourceWantedData
  ): void {
    if (!XmaxLogger.isEnabled(XmaxLoggerOption.PERFORMANCE)) {
      return;
    }
    const state: string = VolcRtcStatsLogger.performanceAlarmName(reason);
    const suggestedFormat: string = VolcRtcStatsLogger.formatSuggestedVideoFormat(data);
    const lines: string[] = ["性能告警 (Performance Alarm)"];

    if (suggestedFormat.length > 0) {
      lines.push(`${XmaxLogger.localized("├─ 状态：", "├─ Status: ")}${state}`);
      lines.push(`${XmaxLogger.localized("└─ 建议：", "└─ Recommendation: ")}${suggestedFormat}`);
    } else {
      lines.push(`${XmaxLogger.localized("└─ 状态：", "└─ Status: ")}${state}`);
    }

    XmaxLogger.debug(
      lines.join('\n'),
      VOLC_LOG_CATEGORY,
      XmaxLoggerOption.PERFORMANCE
    );
  }

  /**
   * Combines network quality with available native metrics.
   *
   * @param quality The uplink, downlink, or combined network quality sample.
   * @param includesRtt Whether to include round-trip latency.
   *
   * @returns The bandwidth, packet loss, and optional RTT text.
   */
  private static formatNetworkMetrics(
    quality: NetworkQualityStats,
    includesRtt: boolean
  ): string {
    const metrics: string[] = [];
    const packetLoss: string = VolcRtcStatsLogger.formatPacketLoss(quality.fraction_lost);
    const bandwidth: string = VolcRtcStatsLogger.formatBandwidth(quality.total_bandwidth);

    if (packetLoss.length > 0) {
      metrics.push(packetLoss);
    }

    if (includesRtt) {
      metrics.push(`RTT ${quality.rtt} ms`);
    }

    metrics.push(`${XmaxLogger.localized("带宽 ", "Bandwidth ")}${bandwidth}`);

    return `${XmaxLogger.localized("指标：", "Metrics: ")}${metrics.join(XmaxLogger.localized('，', ', '))}`;
  }

  /**
   * Returns a readable native network quality name.
   *
   * @param quality The uplink, downlink, or combined network quality sample.
   *
   * @returns The network quality name for logging.
   */
  private static networkQualityName(
    quality: NetworkQuality
  ): string {
    switch (quality) {
      case NetworkQuality.kNetworkQualityExcellent:
        return XmaxLogger.localized(
          "极好",
          "Excellent"
        );
      case NetworkQuality.kNetworkQualityGood:
        return XmaxLogger.localized(
          "良好",
          "Good"
        );
      case NetworkQuality.kNetworkQualityPoor:
        return XmaxLogger.localized(
          "较差",
          "Fair"
        );
      case NetworkQuality.kNetworkQualityBad:
        return XmaxLogger.localized(
          "差",
          "Poor"
        );
      case NetworkQuality.kNetworkQualityVbad:
        return XmaxLogger.localized(
          "极差",
          "Very Poor"
        );
      case NetworkQuality.kNetworkQualityDown:
        return XmaxLogger.localized(
          "断网",
          "Disconnected"
        );
      default:
        return XmaxLogger.localized(
          "未知",
          "Unknown"
        );
    }
  }

  /**
   * Returns a readable performance alarm name.
   *
   * @param reason The termination reason or platform alarm reason.
   *
   * @returns The alarm name for logging.
   */
  private static performanceAlarmName(
    reason: PerformanceAlarmReason
  ): string {
    switch (reason) {
      case PerformanceAlarmReason.kPerformanceAlarmReasonBandwidthFallbacked:
        return XmaxLogger.localized(
          "网络受限",
          "Network Constrained"
        );
      case PerformanceAlarmReason.kPerformanceAlarmReasonBandwidthResumed:
        return XmaxLogger.localized(
          "网络恢复",
          "Network Recovered"
        );
      case PerformanceAlarmReason.kPerformanceAlarmReasonPerformanceFallbacked:
        return XmaxLogger.localized(
          "设备性能受限",
          "Device Performance Constrained"
        );
      case PerformanceAlarmReason.kPerformanceAlarmReasonPerformanceResumed:
        return XmaxLogger.localized(
          "设备性能恢复",
          "Device Performance Recovered"
        );
      default:
        return XmaxLogger.localized(
          "未知",
          "Unknown"
        );
    }
  }

  /**
   * Formats the video format recommended by a performance alarm.
   *
   * @param data The capture dimensions and frame rate recommended by the RTC performance alarm.
   *
   * @returns The recommended dimensions and frame rate text.
   */
  private static formatSuggestedVideoFormat(
    data: SourceWantedData
  ): string {
    if (!VolcRtcStatsLogger.isPositiveNumber(data.width) ||
      !VolcRtcStatsLogger.isPositiveNumber(data.heigth) ||
      !VolcRtcStatsLogger.isPositiveNumber(data.frame_rate)) {
      return '';
    }

    return `${data.width} × ${data.heigth}，${data.frame_rate} fps`;
  }

  /**
   * Formats bandwidth for logging.
   *
   * @param bitsPerSecond The raw bandwidth, in bits per second.
   *
   * @returns The bandwidth text, in kbps.
   */
  private static formatBandwidth(
    bitsPerSecond: number
  ): string {
    return `${(bitsPerSecond / 1000).toFixed(0)} kbps`;
  }

  /**
   * Formats packet loss as a percentage.
   *
   * @param value The reported packet loss fraction.
   *
   * @returns The percentage text, or a missing-value marker if invalid.
   */
  private static formatPacketLoss(
    value: number
  ): string {
    if (typeof value !== 'number' || !Number.isFinite(value)) {
      return '';
    }

    return `${XmaxLogger.localized("丢包 ", "Packet Loss ")}${(value * 100).toFixed(2)}%`;
  }

  /**
   * Checks whether a value is finite.
   *
   * @param value The reported metric to check.
   *
   * @returns True if finite.
   */
  private static isFiniteNumber(
    value: number
  ): boolean {
    return typeof value === 'number' && Number.isFinite(value);
  }

  /**
   * Checks whether a value is finite and positive.
   *
   * @param value The value to check.
   *
   * @returns True if finite and greater than zero.
   */
  private static isPositiveNumber(
    value: number
  ): boolean {
    return VolcRtcStatsLogger.isFiniteNumber(value) && value > 0;
  }
}
