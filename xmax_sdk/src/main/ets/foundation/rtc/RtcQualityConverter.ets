//
//  RtcQualityConverter.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
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

/** 将 RTC 原始质量事件和视频统计转换为 SDK 的统一指标模型。 */
export class RtcQualityConverter {
  /**
   * 将 RTC 上行统计转换为统一视频指标，保留有效的零值并过滤无效值。
   *
   * @param stats RTC 原始视频统计。
   * @returns 使用像素、fps、kbps 和百分数单位的上行视频统计。
   */
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

  /**
   * 将 RTC 下行统计转换为统一视频指标，并关联远端用户。
   *
   * @param userId RTC 用户标识。
   * @param stats RTC 原始视频统计。
   * @returns 使用统一单位并包含远端用户标识的下行视频统计。
   */
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

  /**
   * 校验视频尺寸指标，仅保留安全正整数。
   *
   * @param value 待校验、转换或保存的数值。
   * @returns 有效像素尺寸；无效时返回 undefined。
   */
  private static dimension(value: number): number | undefined {
    return Number.isSafeInteger(value) && value > 0 ? value : undefined;
  }

  /**
   * 校验速率、码率或延迟指标，保留有限非负值。
   *
   * @param value 待校验、转换或保存的数值。
   * @returns 有效数值，包含 0；无效时返回 undefined。
   */
  private static nonnegative(value: number): number | undefined {
    return Number.isFinite(value) && value >= 0 ? value : undefined;
  }

  /**
   * 将 RTC 的丢包率小数转换为百分数。
   *
   * @param value 待校验、转换或保存的数值。
   * @returns 0～100 范围内的百分数；原值无效时返回 undefined。
   */
  private static lossPercent(value: number): number | undefined {
    return Number.isFinite(value) && value >= 0 && value <= 1 ? value * 100 : undefined;
  }

  /**
   * 将平台网络质量等级转换为 SDK 统一等级。
   *
   * @param quality 当前方向或上下行的网络质量采样。
   * @returns 对应的 SDK 网络质量等级。
   */
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

  /**
   * 从远端统计中选出最差的有效接收网络质量。
   *
   * @param remoteQualities RTC 返回的各远端用户网络质量统计。
   * @returns 最差的下行网络质量；没有有效统计时返回 UNKNOWN。
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
   * 识别 RTC 性能告警所表达的设备受限状态。
   *
   * @param reason 操作结束原因或平台告警原因。
   * @returns 受限时返回 true，恢复时返回 false，不相关原因返回 undefined。
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
