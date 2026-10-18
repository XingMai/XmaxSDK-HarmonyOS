import { UplinkVideoStatistics, DownlinkVideoStatistics } from './VideoStatistics';
import { XmaxLogger } from '../logging/XmaxLogger';
import { XmaxLoggerOption } from '../logging/XmaxLoggerOption';

const RTC_LOG_CATEGORY: string = 'RTC';

/** 公共视频统计日志只消费 SDK 模型，与业务回调共享转换与缺失值语义。 */
export class RtcStatsLogger {
  static logUplinkVideoStatistics(video: UplinkVideoStatistics): void {
    XmaxLogger.debug((): string => RtcStatsLogger.uplinkVideoStatisticsMessage(video),
      RTC_LOG_CATEGORY, XmaxLoggerOption.PERFORMANCE);
  }

  static uplinkVideoStatisticsMessage(video: UplinkVideoStatistics): string {
    return '视频上行统计 (Video Uplink Statistics)' +
      `\n├─ ${XmaxLogger.localized('分辨率：', 'Resolution: ')}${RtcStatsLogger.resolution(video.width, video.height)}` +
      `\n├─ ${XmaxLogger.localized('发送码率：', 'Send Bitrate: ')}${RtcStatsLogger.value(video.bitrateKbps, 'kbps')}` +
      `\n├─ ${XmaxLogger.localized('采集帧率：', 'Capture Frame Rate: ')}${RtcStatsLogger.value(video.captureFrameRate, 'fps')}` +
      `\n├─ ${XmaxLogger.localized('编码帧率：', 'Encode Frame Rate: ')}${RtcStatsLogger.value(video.encodeFrameRate, 'fps')}` +
      `\n├─ ${XmaxLogger.localized('发送帧率：', 'Send Frame Rate: ')}${RtcStatsLogger.value(video.sendFrameRate, 'fps')}` +
      `\n└─ ${XmaxLogger.localized('视频丢包率：', 'Video Packet Loss: ')}${RtcStatsLogger.value(video.packetLossPercent, '%')}`;
  }

  static logDownlinkVideoStatistics(video: DownlinkVideoStatistics): void {
    XmaxLogger.debug((): string => RtcStatsLogger.downlinkVideoStatisticsMessage(video),
      RTC_LOG_CATEGORY, XmaxLoggerOption.PERFORMANCE);
  }

  static downlinkVideoStatisticsMessage(video: DownlinkVideoStatistics): string {
    return '视频下行统计 (Video Downlink Statistics)' +
      `\n├─ ${XmaxLogger.localized('分辨率：', 'Resolution: ')}${RtcStatsLogger.resolution(video.width, video.height)}` +
      `\n├─ ${XmaxLogger.localized('接收码率：', 'Receive Bitrate: ')}${RtcStatsLogger.value(video.bitrateKbps, 'kbps')}` +
      `\n├─ ${XmaxLogger.localized('解码帧率：', 'Decode Frame Rate: ')}${RtcStatsLogger.value(video.decodeFrameRate, 'fps')}` +
      `\n├─ ${XmaxLogger.localized('渲染帧率：', 'Render Frame Rate: ')}${RtcStatsLogger.value(video.renderFrameRate, 'fps')}` +
      `\n├─ ${XmaxLogger.localized('视频丢包率：', 'Video Packet Loss: ')}${RtcStatsLogger.value(video.packetLossPercent, '%')}` +
      `\n└─ ${XmaxLogger.localized('端到端时延：', 'End-to-End Delay: ')}${RtcStatsLogger.value(video.endToEndDelayMs, 'ms')}`;
  }

  private static resolution(width: number | undefined, height: number | undefined): string {
    return width === undefined || height === undefined ? '—' : `${width} × ${height}`;
  }

  private static value(value: number | undefined, unit: string): string {
    return value === undefined ? '—' : `${value} ${unit}`;
  }
}
