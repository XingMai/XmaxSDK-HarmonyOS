import {
  LocalVideoStats,
  RemoteVideoStats,
  NetworkQuality,
  NetworkQualityStats,
  PerformanceAlarmReason
} from '@bytertc/volcenginertc';
import { UplinkVideoStatistics, DownlinkVideoStatistics } from './VideoStatistics';
import { RtcQualityLevel } from './RtcQualityListener';

export class RtcQualityConverter {
  static uplinkVideoStatistics(stats: LocalVideoStats): UplinkVideoStatistics {
    return new UplinkVideoStatistics(
      RtcQualityConverter.dimension(stats.encoded_frame_width),
      RtcQualityConverter.dimension(stats.encoded_frame_height),
      RtcQualityConverter.nonnegative(stats.input_frame_rate),
      RtcQualityConverter.nonnegative(stats.encoder_output_frame_rate),
      RtcQualityConverter.nonnegative(stats.sent_frame_rate),
      RtcQualityConverter.nonnegative(stats.sent_kbitrate),
      RtcQualityConverter.lossPercent(stats.video_loss_rate)
    );
  }

  static downlinkVideoStatistics(userId: string, stats: RemoteVideoStats): DownlinkVideoStatistics {
    return new DownlinkVideoStatistics(
      userId,
      RtcQualityConverter.dimension(stats.width),
      RtcQualityConverter.dimension(stats.height),
      RtcQualityConverter.nonnegative(stats.decoder_output_frame_rate),
      RtcQualityConverter.nonnegative(stats.renderer_output_frame_rate),
      RtcQualityConverter.nonnegative(stats.received_kbitrate),
      RtcQualityConverter.lossPercent(stats.video_loss_rate),
      RtcQualityConverter.nonnegative(stats.e2e_delay)
    );
  }

  private static dimension(value: number): number | undefined {
    return Number.isSafeInteger(value) && value > 0 ? value : undefined;
  }

  private static nonnegative(value: number): number | undefined {
    return Number.isFinite(value) && value >= 0 ? value : undefined;
  }

  private static lossPercent(value: number): number | undefined {
    return Number.isFinite(value) && value >= 0 && value <= 1 ? value * 100 : undefined;
  }

  static convertLevel(quality: NetworkQuality): RtcQualityLevel {
    switch (quality) {
      case NetworkQuality.kNetworkQualityExcellent:
        return RtcQualityLevel.EXCELLENT;
      case NetworkQuality.kNetworkQualityGood:
        return RtcQualityLevel.GOOD;
      case NetworkQuality.kNetworkQualityPoor:
        return RtcQualityLevel.POOR;
      case NetworkQuality.kNetworkQualityBad:
        return RtcQualityLevel.BAD;
      case NetworkQuality.kNetworkQualityVbad:
        return RtcQualityLevel.VERY_BAD;
      case NetworkQuality.kNetworkQualityDown:
        return RtcQualityLevel.DOWN;
      default:
        return RtcQualityLevel.UNKNOWN;
    }
  }

  static resolveDownlinkLevel(
    remoteQualities: NetworkQualityStats[]
  ): RtcQualityLevel {
    let quality: NetworkQuality = NetworkQuality.kNetworkQualityUnknown;

    remoteQualities.forEach((statistics: NetworkQualityStats): void => {
      const remoteQuality: NetworkQuality = statistics.rx_quality;
      if (typeof remoteQuality === 'number' && remoteQuality > quality &&
        remoteQuality <= NetworkQuality.kNetworkQualityDown) {
        quality = remoteQuality;
      }
    });

    return RtcQualityConverter.convertLevel(quality);
  }

  static resolvePerformanceLimited(
    reason: PerformanceAlarmReason
  ): boolean | undefined {
    switch (reason) {
      case PerformanceAlarmReason.kPerformanceAlarmReasonBandwidthFallbacked:
      case PerformanceAlarmReason.kPerformanceAlarmReasonPerformanceFallbacked:
        return true;
      case PerformanceAlarmReason.kPerformanceAlarmReasonBandwidthResumed:
      case PerformanceAlarmReason.kPerformanceAlarmReasonPerformanceResumed:
        return false;
      default:
        return undefined;
    }
  }
}
