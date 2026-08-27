import {
  LocalStreamStats,
  NetworkQuality,
  NetworkQualityStats,
  PerformanceAlarmReason,
  RemoteStreamStats,
  SourceWantedData,
  SysStats
} from '@bytertc/volcenginertc';
import { XmaxLogger } from '../logging/XmaxLogger';

const RTC_LOG_CATEGORY: string = 'RTC';

export class RtcStatsLogger {
  static logLocalStreamStats(stats: LocalStreamStats): void {
    const audio = stats.audio_stats;
    const video = stats.video_stats;

    XmaxLogger.debug(
      `本地视频发送
├─ 分辨率：${video.encoded_frame_width} × ${video.encoded_frame_height}
├─ 码率：${video.sent_kbitrate} kbps
├─ 帧率：采集 ${video.input_frame_rate} fps，编码 ${video.encoder_output_frame_rate} fps，发送 ${video.sent_frame_rate} fps
├─ 网络：丢包 ${(video.video_loss_rate * 100).toFixed(2)}%，RTT ${video.rtt} ms${RtcStatsLogger.formatJitter(video.jitter)}
└─ 音频：${audio.send_kbitrate} kbps，采集 ${audio.record_sample_rate} Hz，发送 ${audio.sent_sample_rate} Hz，${audio.num_channels} 声道`,
      RTC_LOG_CATEGORY
    );
  }

  static logRemoteStreamStats(stats: RemoteStreamStats): void {
    const video = stats.video_stats;

    XmaxLogger.debug(
      `远端视频接收
├─ 分辨率：${video.width} × ${video.height}
├─ 码率：${video.received_kbitrate} kbps
├─ 帧率：解码 ${video.decoder_output_frame_rate} fps，渲染 ${video.renderer_output_frame_rate} fps
├─ 网络：丢包 ${(video.video_loss_rate * 100).toFixed(2)}%，RTT ${video.rtt} ms${RtcStatsLogger.formatJitter(video.jitter)}
├─ 卡顿：${video.stall_count} 次，${video.stall_duration} ms
└─ 时延：端到端 ${video.e2e_delay} ms`,
      RTC_LOG_CATEGORY
    );
  }

  static logNetworkQuality(
    localQuality: NetworkQualityStats,
    remoteQualities: NetworkQualityStats[]
  ): void {
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
      '网络质量',
      `${localBranch} 本地发送（上行）`,
      `${localIndent}├─ 质量：${localQualityText}`,
      `${localIndent}└─ ${localMetricsText}`
    ];

    remoteQualities.forEach((quality: NetworkQualityStats, index: number): void => {
      const isLast: boolean = index === remoteQualities.length - 1;
      const branch: string = isLast ? '└─' : '├─';
      const indent: string = isLast ? '   ' : '│  ';
      const qualityText: string = RtcStatsLogger.networkQualityName(quality.rx_quality);
      const metricsText: string = RtcStatsLogger.formatNetworkMetrics(quality, false);

      lines.push(`${branch} 远端接收 ${quality.uid}（下行）`);
      lines.push(`${indent}├─ 质量：${qualityText}`);
      lines.push(`${indent}└─ ${metricsText}`);
    });

    XmaxLogger.debug(lines.join('\n'), RTC_LOG_CATEGORY);
  }

  static logSystemStats(stats: SysStats): void {
    const cpuMetrics: string[] = RtcStatsLogger.formatCpuMetrics(stats);
    const memoryMetrics: string[] = RtcStatsLogger.formatMemoryMetrics(stats);
    const metrics: string[] = [];

    if (cpuMetrics.length > 0) {
      metrics.push(`CPU：${cpuMetrics.join('，')}`);
    }

    if (memoryMetrics.length > 0) {
      metrics.push(`内存：${memoryMetrics.join('，')}`);
    }

    if (metrics.length === 0) {
      return;
    }

    const lines: string[] = ['性能统计'];
    metrics.forEach((metric: string, index: number): void => {
      const branch: string = index === metrics.length - 1 ? '└─' : '├─';
      lines.push(`${branch} ${metric}`);
    });

    XmaxLogger.debug(lines.join('\n'), RTC_LOG_CATEGORY);
  }

  static logPerformanceAlarm(
    reason: PerformanceAlarmReason,
    data: SourceWantedData
  ): void {
    const state: string = RtcStatsLogger.performanceAlarmName(reason);
    const suggestedFormat: string = RtcStatsLogger.formatSuggestedVideoFormat(data);
    const lines: string[] = ['性能告警'];

    if (suggestedFormat.length > 0) {
      lines.push(`├─ 状态：${state}`);
      lines.push(`└─ 建议：${suggestedFormat}`);
    } else {
      lines.push(`└─ 状态：${state}`);
    }

    XmaxLogger.debug(lines.join('\n'), RTC_LOG_CATEGORY);
  }

  private static formatJitter(value: number): string {
    if (typeof value !== 'number' || !Number.isFinite(value)) {
      return '';
    }

    return `，抖动 ${value} ms`;
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

    metrics.push(`带宽 ${bandwidth}`);

    return `指标：${metrics.join('，')}`;
  }

  private static formatCpuMetrics(stats: SysStats): string[] {
    const metrics: string[] = [];

    if (RtcStatsLogger.isFiniteNumber(stats.cpu_app_usage)) {
      metrics.push(`应用 ${(stats.cpu_app_usage * 100).toFixed(2)}%`);
    }

    if (RtcStatsLogger.isFiniteNumber(stats.cpu_total_usage)) {
      metrics.push(`系统 ${(stats.cpu_total_usage * 100).toFixed(2)}%`);
    }

    if (RtcStatsLogger.isFiniteNumber(stats.cpu_cores)) {
      metrics.push(`${stats.cpu_cores} 核`);
    }

    return metrics;
  }

  private static formatMemoryMetrics(stats: SysStats): string[] {
    const metrics: string[] = [];

    if (RtcStatsLogger.isFiniteNumber(stats.memory_usage)) {
      metrics.push(`应用 ${stats.memory_usage.toFixed(0)} MB`);
    }

    if (RtcStatsLogger.isFiniteNumber(stats.memory_ratio)) {
      metrics.push(`应用占用 ${stats.memory_ratio.toFixed(2)}%`);
    }

    if (RtcStatsLogger.isFiniteNumber(stats.total_memory_ratio)) {
      metrics.push(`系统占用 ${stats.total_memory_ratio.toFixed(2)}%`);
    }

    return metrics;
  }

  private static networkQualityName(quality: NetworkQuality): string {
    switch (quality) {
      case NetworkQuality.kNetworkQualityExcellent:
        return '极好';
      case NetworkQuality.kNetworkQualityGood:
        return '良好';
      case NetworkQuality.kNetworkQualityPoor:
        return '较差';
      case NetworkQuality.kNetworkQualityBad:
        return '差';
      case NetworkQuality.kNetworkQualityVbad:
        return '极差';
      case NetworkQuality.kNetworkQualityDown:
        return '断网';
      default:
        return '未知';
    }
  }

  private static performanceAlarmName(reason: PerformanceAlarmReason): string {
    switch (reason) {
      case PerformanceAlarmReason.kPerformanceAlarmReasonBandwidthFallbacked:
        return '网络受限';
      case PerformanceAlarmReason.kPerformanceAlarmReasonBandwidthResumed:
        return '网络恢复';
      case PerformanceAlarmReason.kPerformanceAlarmReasonPerformanceFallbacked:
        return '设备性能受限';
      case PerformanceAlarmReason.kPerformanceAlarmReasonPerformanceResumed:
        return '设备性能恢复';
      default:
        return '未知';
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

    return `丢包 ${(value * 100).toFixed(2)}%`;
  }

  private static isFiniteNumber(value: number): boolean {
    return typeof value === 'number' && Number.isFinite(value);
  }

  private static isPositiveNumber(value: number): boolean {
    return RtcStatsLogger.isFiniteNumber(value) && value > 0;
  }
}
