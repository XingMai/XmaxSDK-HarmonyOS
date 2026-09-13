import {
  LocalStreamStats,
  NetworkQuality,
  NetworkQualityStats,
  PerformanceAlarmReason,
  RemoteStreamStats,
  SourceWantedData
} from '@bytertc/volcenginertc';
import { XmaxLogger } from '../logging/XmaxLogger';
import { XmaxLoggerOption } from '../logging/XmaxLoggerOption';

const RTC_LOG_CATEGORY: string = 'RTC';

export class RtcStatsLogger {
  static logLocalStreamStats(stats: LocalStreamStats): void {
    if (!XmaxLogger.isEnabled(XmaxLoggerOption.PERFORMANCE)) {
      return;
    }
    const audio = stats.audio_stats;
    const video = stats.video_stats;

    XmaxLogger.debug(
      `${XmaxLogger.localized("本地视频发送 (Local Video Send)\n├─ 分辨率：", "本地视频发送 (Local Video Send)\n├─ Resolution: ")}${video.encoded_frame_width} × ${video.encoded_frame_height}` +
      `${XmaxLogger.localized("\n├─ 码率：", "\n├─ Bitrate: ")}${video.sent_kbitrate}` +
      `${XmaxLogger.localized(" kbps\n├─ 帧率：采集 ", " kbps\n├─ Frame Rate: Capture ")}${video.input_frame_rate}` +
      `${XmaxLogger.localized(" fps，编码 ", " fps, Encode ")}${video.encoder_output_frame_rate}` +
      `${XmaxLogger.localized(" fps，发送 ", " fps, Send ")}${video.sent_frame_rate}` +
      `${XmaxLogger.localized(" fps\n├─ 网络：丢包 ", " fps\n├─ Network: Packet Loss ")}${(video.video_loss_rate * 100).toFixed(2)}%${XmaxLogger.localized('，', ', ')}RTT ${video.rtt} ms${RtcStatsLogger.formatJitter(video.jitter)}` +
      `${XmaxLogger.localized("\n└─ 音频：", "\n└─ Audio: ")}${audio.send_kbitrate}` +
      `${XmaxLogger.localized(" kbps，采集 ", " kbps, Capture ")}${audio.record_sample_rate}` +
      `${XmaxLogger.localized(" Hz，发送 ", " Hz, Send ")}${audio.sent_sample_rate} Hz${XmaxLogger.localized('，', ', ')}${audio.num_channels}` +
      `${XmaxLogger.localized(" 声道", " Channels")}`,
      RTC_LOG_CATEGORY,
      XmaxLoggerOption.PERFORMANCE
    );
  }

  static logRemoteStreamStats(stats: RemoteStreamStats): void {
    if (!XmaxLogger.isEnabled(XmaxLoggerOption.PERFORMANCE)) {
      return;
    }
    const video = stats.video_stats;

    XmaxLogger.debug(
      `${XmaxLogger.localized("远端视频接收 (Remote Video Receive)\n├─ 分辨率：", "远端视频接收 (Remote Video Receive)\n├─ Resolution: ")}${video.width} × ${video.height}` +
      `${XmaxLogger.localized("\n├─ 码率：", "\n├─ Bitrate: ")}${video.received_kbitrate}` +
      `${XmaxLogger.localized(" kbps\n├─ 帧率：解码 ", " kbps\n├─ Frame Rate: Decode ")}${video.decoder_output_frame_rate}` +
      `${XmaxLogger.localized(" fps，渲染 ", " fps, Render ")}${video.renderer_output_frame_rate}` +
      `${XmaxLogger.localized(" fps\n├─ 网络：丢包 ", " fps\n├─ Network: Packet Loss ")}${(video.video_loss_rate * 100).toFixed(2)}%${XmaxLogger.localized('，', ', ')}RTT ${video.rtt} ms${RtcStatsLogger.formatJitter(video.jitter)}` +
      `${XmaxLogger.localized("\n├─ 卡顿：", "\n├─ Stalls: ")}${video.stall_count}` +
      `${XmaxLogger.localized(" 次，", " times, ")}${video.stall_duration}` +
      `${XmaxLogger.localized(" ms\n└─ 时延：端到端 ", " ms\n└─ Delay: End-to-end ")}${video.e2e_delay} ms`,
      RTC_LOG_CATEGORY,
      XmaxLoggerOption.PERFORMANCE
    );
  }

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
    const localQualityText: string = RtcStatsLogger.networkQualityName(
      localQuality.tx_quality
    );
    const localMetricsText: string = RtcStatsLogger.formatNetworkMetrics(
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
      const qualityText: string = RtcStatsLogger.networkQualityName(quality.rx_quality);
      const metricsText: string = RtcStatsLogger.formatNetworkMetrics(quality, false);

      lines.push(`${branch}${XmaxLogger.localized(" 远端接收 ", " Remote Receive ")}${quality.uid}${XmaxLogger.localized("（下行）", " (Downlink)")}`);
      lines.push(`${indent}${XmaxLogger.localized("├─ 质量：", "├─ Quality: ")}${qualityText}`);
      lines.push(`${indent}└─ ${metricsText}`);
    });

    XmaxLogger.debug(lines.join('\n'), RTC_LOG_CATEGORY, XmaxLoggerOption.PERFORMANCE);
  }

  static logPerformanceAlarm(
    reason: PerformanceAlarmReason,
    data: SourceWantedData
  ): void {
    if (!XmaxLogger.isEnabled(XmaxLoggerOption.PERFORMANCE)) {
      return;
    }
    const state: string = RtcStatsLogger.performanceAlarmName(reason);
    const suggestedFormat: string = RtcStatsLogger.formatSuggestedVideoFormat(data);
    const lines: string[] = ["性能告警 (Performance Alarm)"];

    if (suggestedFormat.length > 0) {
      lines.push(`${XmaxLogger.localized("├─ 状态：", "├─ Status: ")}${state}`);
      lines.push(`${XmaxLogger.localized("└─ 建议：", "└─ Recommendation: ")}${suggestedFormat}`);
    } else {
      lines.push(`${XmaxLogger.localized("└─ 状态：", "└─ Status: ")}${state}`);
    }

    XmaxLogger.debug(lines.join('\n'), RTC_LOG_CATEGORY, XmaxLoggerOption.PERFORMANCE);
  }

  private static formatJitter(value: number): string {
    if (typeof value !== 'number' || !Number.isFinite(value)) {
      return '';
    }

    return `${XmaxLogger.localized("，抖动 ", ", Jitter ")}${value} ms`;
  }

  private static formatNetworkMetrics(
    quality: NetworkQualityStats,
    includesRtt: boolean
  ): string {
    const metrics: string[] = [];
    const packetLoss: string = RtcStatsLogger.formatPacketLoss(quality.fraction_lost);
    const bandwidth: string = RtcStatsLogger.formatBandwidth(quality.total_bandwidth);

    if (packetLoss.length > 0) {
      metrics.push(packetLoss);
    }

    if (includesRtt) {
      metrics.push(`RTT ${quality.rtt} ms`);
    }

    metrics.push(`${XmaxLogger.localized("带宽 ", "Bandwidth ")}${bandwidth}`);

    return `${XmaxLogger.localized("指标：", "Metrics: ")}${metrics.join(XmaxLogger.localized('，', ', '))}`;
  }

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

  private static formatSuggestedVideoFormat(data: SourceWantedData): string {
    if (!RtcStatsLogger.isPositiveNumber(data.width) ||
      !RtcStatsLogger.isPositiveNumber(data.heigth) ||
      !RtcStatsLogger.isPositiveNumber(data.frame_rate)) {
      return '';
    }

    return `${data.width} × ${data.heigth}，${data.frame_rate} fps`;
  }

  private static formatBandwidth(bitsPerSecond: number): string {
    return `${(bitsPerSecond / 1000).toFixed(0)} kbps`;
  }

  private static formatPacketLoss(value: number): string {
    if (typeof value !== 'number' || !Number.isFinite(value)) {
      return '';
    }

    return `${XmaxLogger.localized("丢包 ", "Packet Loss ")}${(value * 100).toFixed(2)}%`;
  }

  private static isFiniteNumber(value: number): boolean {
    return typeof value === 'number' && Number.isFinite(value);
  }

  private static isPositiveNumber(value: number): boolean {
    return RtcStatsLogger.isFiniteNumber(value) && value > 0;
  }
}
