//
//  RtcStatsLogger.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { UplinkVideoStatistics, DownlinkVideoStatistics } from './VideoStatistics';
import { XmaxLogger } from '../logging/XmaxLogger';
import { XmaxLoggerOption } from '../logging/XmaxLoggerOption';

const RTC_LOG_CATEGORY: string = 'RTC';

/**
 * Public statistics logs use SDK models, sharing conversion and missing-value semantics with
 * application callbacks.
 */
export class RtcStatsLogger {

  /**
   * Logs normalized uplink metrics when performance logging is enabled.
   *
   * @param video The normalized uplink or downlink video statistics.
   */
  static logUplinkVideoStatistics(
    video: UplinkVideoStatistics
  ): void {
    XmaxLogger.debug(
      (): string => RtcStatsLogger.uplinkVideoStatisticsMessage(video),
      RTC_LOG_CATEGORY,
      XmaxLoggerOption.PERFORMANCE
    );
  }

  /**
   * Formats normalized uplink metrics with units.
   *
   * @param video The normalized uplink or downlink video statistics.
   *
   * @returns The uplink statistics text, using a dash for missing values.
   */
  static uplinkVideoStatisticsMessage(
    video: UplinkVideoStatistics
  ): string {
    return '视频上行统计 (Video Uplink Statistics)' +
      `\n├─ ${XmaxLogger.localized('分辨率：', 'Resolution: ')}${RtcStatsLogger.resolution(video.width, video.height)}` +
      `\n├─ ${XmaxLogger.localized('发送码率：', 'Send Bitrate: ')}${RtcStatsLogger.value(video.bitrateKbps, 'kbps')}` +
      `\n├─ ${XmaxLogger.localized('采集帧率：', 'Capture Frame Rate: ')}${RtcStatsLogger.value(video.captureFrameRate, 'fps')}` +
      `\n├─ ${XmaxLogger.localized('编码帧率：', 'Encode Frame Rate: ')}${RtcStatsLogger.value(video.encodeFrameRate, 'fps')}` +
      `\n├─ ${XmaxLogger.localized('发送帧率：', 'Send Frame Rate: ')}${RtcStatsLogger.value(video.sendFrameRate, 'fps')}` +
      `\n└─ ${XmaxLogger.localized('视频丢包率：', 'Video Packet Loss: ')}${RtcStatsLogger.value(video.packetLossPercent, '%')}`;
  }

  /**
   * Logs normalized downlink metrics when performance logging is enabled.
   *
   * @param video The normalized uplink or downlink video statistics.
   */
  static logDownlinkVideoStatistics(
    video: DownlinkVideoStatistics
  ): void {
    XmaxLogger.debug(
      (): string => RtcStatsLogger.downlinkVideoStatisticsMessage(video),
      RTC_LOG_CATEGORY,
      XmaxLoggerOption.PERFORMANCE
    );
  }

  /**
   * Formats normalized downlink metrics with units.
   *
   * @param video The normalized uplink or downlink video statistics.
   *
   * @returns The downlink statistics text, using a dash for missing values.
   */
  static downlinkVideoStatisticsMessage(
    video: DownlinkVideoStatistics
  ): string {
    return '视频下行统计 (Video Downlink Statistics)' +
      `\n├─ ${XmaxLogger.localized('分辨率：', 'Resolution: ')}${RtcStatsLogger.resolution(video.width, video.height)}` +
      `\n├─ ${XmaxLogger.localized('接收码率：', 'Receive Bitrate: ')}${RtcStatsLogger.value(video.bitrateKbps, 'kbps')}` +
      `\n├─ ${XmaxLogger.localized('解码帧率：', 'Decode Frame Rate: ')}${RtcStatsLogger.value(video.decodeFrameRate, 'fps')}` +
      `\n├─ ${XmaxLogger.localized('渲染帧率：', 'Render Frame Rate: ')}${RtcStatsLogger.value(video.renderFrameRate, 'fps')}` +
      `\n├─ ${XmaxLogger.localized('视频丢包率：', 'Video Packet Loss: ')}${RtcStatsLogger.value(video.packetLossPercent, '%')}` +
      `\n└─ ${XmaxLogger.localized('端到端时延：', 'End-to-End Delay: ')}${RtcStatsLogger.value(video.endToEndDelayMs, 'ms')}`;
  }

  /**
   * Formats valid width and height as a resolution.
   *
   * @param width The frame width, in pixels.
   * @param height The frame height, in pixels.
   *
   * @returns The resolution, or a dash if either dimension is invalid.
   */
  private static resolution(
    width: number | undefined,
    height: number | undefined
  ): string {
    return width === undefined || height === undefined ? '—' : `${width} × ${height}`;
  }

  /**
   * Formats a metric with its unit.
   *
   * @param value The reported metric, or undefined to display a dash.
   * @param unit The metric display unit.
   *
   * @returns The value and unit, or a dash if unavailable.
   */
  private static value(
    value: number | undefined,
    unit: string
  ): string {
    return value === undefined ? '—' : `${value} ${unit}`;
  }
}
