//
//  RtcStatsLogger.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { UplinkVideoStatistics, DownlinkVideoStatistics } from './VideoStatistics';
import { XmaxLogger } from '../logging/XmaxLogger';
import { XmaxLoggerOption } from '../logging/XmaxLoggerOption';

const RTC_LOG_CATEGORY: string = 'RTC';

/** 公共视频统计日志只消费 SDK 模型，与业务回调共享转换与缺失值语义。 */
export class RtcStatsLogger {
  /**
   * 按性能日志配置输出统一上行视频指标。
   *
   * @param video 统一的上行或下行视频统计。
   * @returns 无返回值。
   */
  static logUplinkVideoStatistics(video: UplinkVideoStatistics): void {
    XmaxLogger.debug((): string => RtcStatsLogger.uplinkVideoStatisticsMessage(video),
      RTC_LOG_CATEGORY, XmaxLoggerOption.PERFORMANCE);
  }

  /**
   * 将统一上行视频指标转换为包含单位的日志文本。
   *
   * @param video 统一的上行或下行视频统计。
   * @returns 可直接输出的上行视频统计文本；缺失指标显示为破折号。
   */
  static uplinkVideoStatisticsMessage(video: UplinkVideoStatistics): string {
    return '视频上行统计 (Video Uplink Statistics)' +
      `\n├─ ${XmaxLogger.localized('分辨率：', 'Resolution: ')}${RtcStatsLogger.resolution(video.width, video.height)}` +
      `\n├─ ${XmaxLogger.localized('发送码率：', 'Send Bitrate: ')}${RtcStatsLogger.value(video.bitrateKbps, 'kbps')}` +
      `\n├─ ${XmaxLogger.localized('采集帧率：', 'Capture Frame Rate: ')}${RtcStatsLogger.value(video.captureFrameRate, 'fps')}` +
      `\n├─ ${XmaxLogger.localized('编码帧率：', 'Encode Frame Rate: ')}${RtcStatsLogger.value(video.encodeFrameRate, 'fps')}` +
      `\n├─ ${XmaxLogger.localized('发送帧率：', 'Send Frame Rate: ')}${RtcStatsLogger.value(video.sendFrameRate, 'fps')}` +
      `\n└─ ${XmaxLogger.localized('视频丢包率：', 'Video Packet Loss: ')}${RtcStatsLogger.value(video.packetLossPercent, '%')}`;
  }

  /**
   * 按性能日志配置输出统一下行视频指标。
   *
   * @param video 统一的上行或下行视频统计。
   * @returns 无返回值。
   */
  static logDownlinkVideoStatistics(video: DownlinkVideoStatistics): void {
    XmaxLogger.debug((): string => RtcStatsLogger.downlinkVideoStatisticsMessage(video),
      RTC_LOG_CATEGORY, XmaxLoggerOption.PERFORMANCE);
  }

  /**
   * 将统一下行视频指标转换为包含单位的日志文本。
   *
   * @param video 统一的上行或下行视频统计。
   * @returns 可直接输出的下行视频统计文本；缺失指标显示为破折号。
   */
  static downlinkVideoStatisticsMessage(video: DownlinkVideoStatistics): string {
    return '视频下行统计 (Video Downlink Statistics)' +
      `\n├─ ${XmaxLogger.localized('分辨率：', 'Resolution: ')}${RtcStatsLogger.resolution(video.width, video.height)}` +
      `\n├─ ${XmaxLogger.localized('接收码率：', 'Receive Bitrate: ')}${RtcStatsLogger.value(video.bitrateKbps, 'kbps')}` +
      `\n├─ ${XmaxLogger.localized('解码帧率：', 'Decode Frame Rate: ')}${RtcStatsLogger.value(video.decodeFrameRate, 'fps')}` +
      `\n├─ ${XmaxLogger.localized('渲染帧率：', 'Render Frame Rate: ')}${RtcStatsLogger.value(video.renderFrameRate, 'fps')}` +
      `\n├─ ${XmaxLogger.localized('视频丢包率：', 'Video Packet Loss: ')}${RtcStatsLogger.value(video.packetLossPercent, '%')}` +
      `\n└─ ${XmaxLogger.localized('端到端时延：', 'End-to-End Delay: ')}${RtcStatsLogger.value(video.endToEndDelayMs, 'ms')}`;
  }

  /**
   * 将有效宽高组合为分辨率文本。
   *
   * @param width 画面宽度，单位像素。
   * @param height 画面高度，单位像素。
   * @returns 宽高均有效时返回分辨率，否则返回破折号。
   */
  private static resolution(width: number | undefined, height: number | undefined): string {
    return width === undefined || height === undefined ? '—' : `${width} × ${height}`;
  }

  /**
   * 格式化单个指标并附带单位。
   *
   * @param value 待校验、转换或保存的数值。
   * @param unit 指标的显示单位。
   * @returns 数值与单位文本；指标缺失时返回破折号。
   */
  private static value(value: number | undefined, unit: string): string {
    return value === undefined ? '—' : `${value} ${unit}`;
  }
}
