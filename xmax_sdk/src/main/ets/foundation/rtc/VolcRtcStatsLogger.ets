//
//  VolcRtcStatsLogger.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
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

/** 火山 RTC 网络质量与性能告警日志；公共视频指标由 RtcStatsLogger 输出。 */
export class VolcRtcStatsLogger {
  /**
   * 输出 RTC 原生网络质量诊断，包括带宽、丢包和往返时延。
   *
   * @param localQuality 本地 RTC 网络质量统计。
   * @param remoteQualities RTC 返回的各远端用户网络质量统计。
   * @returns 无返回值。
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
      const metricsText: string = VolcRtcStatsLogger.formatNetworkMetrics(quality, false);

      lines.push(`${branch}${XmaxLogger.localized(" 远端接收 ", " Remote Receive ")}${quality.uid}${XmaxLogger.localized("（下行）", " (Downlink)")}`);
      lines.push(`${indent}${XmaxLogger.localized("├─ 质量：", "├─ Quality: ")}${qualityText}`);
      lines.push(`${indent}└─ ${metricsText}`);
    });

    XmaxLogger.debug(lines.join('\n'), VOLC_LOG_CATEGORY, XmaxLoggerOption.PERFORMANCE);
  }

  /**
   * 输出 RTC 原生设备性能告警和建议视频格式。
   *
   * @param reason 操作结束原因或平台告警原因。
   * @param data 当前帧的有效媒体数据。
   * @returns 无返回值。
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

    XmaxLogger.debug(lines.join('\n'), VOLC_LOG_CATEGORY, XmaxLoggerOption.PERFORMANCE);
  }

  /**
   * 组合网络质量等级与可用的原生网络指标。
   *
   * @param quality 当前方向或上下行的网络质量采样。
   * @param includesRtt 是否在日志中包含往返时延。
   * @returns 包含带宽、丢包及可选 RTT 的文本。
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
   * 为原生网络质量等级生成可读名称。
   *
   * @param quality 当前方向或上下行的网络质量采样。
   * @returns 用于日志显示的网络质量名称。
   */
  private static networkQualityName(quality: NetworkQuality): string {
    switch (quality) {
      case NetworkQuality.kNetworkQualityExcellent:
        return XmaxLogger.localized("极好", "Excellent");
      case NetworkQuality.kNetworkQualityGood:
        return XmaxLogger.localized("良好", "Good");
      case NetworkQuality.kNetworkQualityPoor:
        return XmaxLogger.localized("较差", "Fair");
      case NetworkQuality.kNetworkQualityBad:
        return XmaxLogger.localized("差", "Poor");
      case NetworkQuality.kNetworkQualityVbad:
        return XmaxLogger.localized("极差", "Very Poor");
      case NetworkQuality.kNetworkQualityDown:
        return XmaxLogger.localized("断网", "Disconnected");
      default:
        return XmaxLogger.localized("未知", "Unknown");
    }
  }

  /**
   * 为设备性能告警原因生成可读名称。
   *
   * @param reason 操作结束原因或平台告警原因。
   * @returns 用于日志显示的告警名称。
   */
  private static performanceAlarmName(reason: PerformanceAlarmReason): string {
    switch (reason) {
      case PerformanceAlarmReason.kPerformanceAlarmReasonBandwidthFallbacked:
        return XmaxLogger.localized("网络受限", "Network Constrained");
      case PerformanceAlarmReason.kPerformanceAlarmReasonBandwidthResumed:
        return XmaxLogger.localized("网络恢复", "Network Recovered");
      case PerformanceAlarmReason.kPerformanceAlarmReasonPerformanceFallbacked:
        return XmaxLogger.localized("设备性能受限", "Device Performance Constrained");
      case PerformanceAlarmReason.kPerformanceAlarmReasonPerformanceResumed:
        return XmaxLogger.localized("设备性能恢复", "Device Performance Recovered");
      default:
        return XmaxLogger.localized("未知", "Unknown");
    }
  }

  /**
   * 格式化设备性能告警附带的建议视频规格。
   *
   * @param data 当前帧的有效媒体数据。
   * @returns 建议宽高与帧率的文本。
   */
  private static formatSuggestedVideoFormat(data: SourceWantedData): string {
    if (!VolcRtcStatsLogger.isPositiveNumber(data.width) ||
      !VolcRtcStatsLogger.isPositiveNumber(data.heigth) ||
      !VolcRtcStatsLogger.isPositiveNumber(data.frame_rate)) {
      return '';
    }

    return `${data.width} × ${data.heigth}，${data.frame_rate} fps`;
  }

  /**
   * 将带宽值转换为可读日志文本。
   *
   * @param bitsPerSecond 每秒比特数表示的原始带宽。
   * @returns 以 kbps 表示的带宽文本。
   */
  private static formatBandwidth(bitsPerSecond: number): string {
    return `${(bitsPerSecond / 1000).toFixed(0)} kbps`;
  }

  /**
   * 将丢包率转换为百分比日志文本。
   *
   * @param value 待校验、转换或保存的数值。
   * @returns 丢包百分比文本；无效值使用缺失标记。
   */
  private static formatPacketLoss(value: number): string {
    if (typeof value !== 'number' || !Number.isFinite(value)) {
      return '';
    }

    return `${XmaxLogger.localized("丢包 ", "Packet Loss ")}${(value * 100).toFixed(2)}%`;
  }

  /**
   * 判断输入是否为有限数值。
   *
   * @param value 待校验、转换或保存的数值。
   * @returns 数值有限时返回 true。
   */
  private static isFiniteNumber(value: number): boolean {
    return typeof value === 'number' && Number.isFinite(value);
  }

  /**
   * 判断输入是否为有限正数。
   *
   * @param value 待检查数值。
   * @returns 数值有限且大于 0 时返回 true。
   */
  private static isPositiveNumber(value: number): boolean {
    return VolcRtcStatsLogger.isFiniteNumber(value) && value > 0;
  }
}
