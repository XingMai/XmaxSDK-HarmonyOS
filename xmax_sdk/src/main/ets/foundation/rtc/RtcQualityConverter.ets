import {
  NetworkQuality,
  NetworkQualityStats,
  PerformanceAlarmReason
} from '@bytertc/volcenginertc';
import { RtcQualityLevel } from './RtcQualityListener';

export class RtcQualityConverter {
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
