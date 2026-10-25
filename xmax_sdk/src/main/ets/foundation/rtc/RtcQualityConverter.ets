//
//  RtcQualityConverter.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import {
  LocalVideoStats,
  RemoteVideoStats,
  NetworkQuality,
  NetworkQualityStats,
  PerformanceAlarmReason
} from '@bytertc/volcenginertc';
import { UplinkVideoStatistics, DownlinkVideoStatistics } from './VideoStatistics';
import { RtcQualityLevel } from './RtcQualityListener';

/** Converts RTC quality and video statistics into SDK metrics. */
export class RtcQualityConverter {

  /**
   * Normalizes uplink statistics, preserving valid zero values and filtering invalid values.
   *
   * @param stats The raw RTC video statistics.
   *
   * @returns Uplink statistics in pixels, fps, kbps, and percent.
   */
  static uplinkVideoStatistics(
    stats: LocalVideoStats
  ): UplinkVideoStatistics {
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

  /**
   * Normalizes downlink statistics and associates the remote user.
   *
   * @param userId The RTC user identifier.
   * @param stats The raw RTC video statistics.
   *
   * @returns Downlink statistics in SDK units with the remote user identifier.
   */
  static downlinkVideoStatistics(
    userId: string,
    stats: RemoteVideoStats
  ): DownlinkVideoStatistics {
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

  /**
   * Validates positive safe-integer video dimensions.
   *
   * @param value The reported video dimension, in pixels.
   *
   * @returns The valid pixel dimension, or undefined if invalid.
   */
  private static dimension(
    value: number
  ): number | undefined {
    return Number.isSafeInteger(value) && value > 0 ? value : undefined;
  }

  /**
   * Validates rate, bitrate, and latency metrics as finite nonnegative values.
   *
   * @param value The reported rate, bitrate, or latency metric.
   *
   * @returns The valid value, including zero, or undefined if invalid.
   */
  private static nonnegative(
    value: number
  ): number | undefined {
    return Number.isFinite(value) && value >= 0 ? value : undefined;
  }

  /**
   * Converts an RTC packet loss fraction into a percentage.
   *
   * @param value The reported packet loss fraction, from 0 to 1.
   *
   * @returns A percentage in 0 to 100, or undefined if invalid.
   */
  private static lossPercent(
    value: number
  ): number | undefined {
    return Number.isFinite(value) && value >= 0 && value <= 1 ? value * 100 : undefined;
  }

  /**
   * Converts platform network quality into an SDK level.
   *
   * @param quality The uplink, downlink, or combined network quality sample.
   *
   * @returns The corresponding SDK network quality level.
   */
  static convertLevel(
    quality: NetworkQuality
  ): RtcQualityLevel {
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

  /**
   * Selects the worst valid remote receive quality.
   *
   * @param remoteQualities The remote users' RTC network quality statistics.
   *
   * @returns The worst downlink quality, or UNKNOWN if no valid sample exists.
   */
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

  /**
   * Resolves device limitation state from an RTC performance alarm.
   *
   * @param reason The termination reason or platform alarm reason.
   *
   * @returns True if limited, false if recovered, or undefined for an unrelated reason.
   */
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
