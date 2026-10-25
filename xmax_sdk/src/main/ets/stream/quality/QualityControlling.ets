//
//  QualityControlling.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { UplinkVideoStatisticsListener, DownlinkVideoStatisticsListener } from '../../foundation/rtc/VideoStatistics';
import { QualityConfiguration, QualityChange, AdaptiveQualityListener } from './QualityConfiguration';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import { RealtimeNetworkQuality } from '../../service/realtime/RealtimeNetworkQuality';
import { RealtimeNetworkQualityListener } from '../../service/realtime/RealtimeNetworkQuality';
import { RealtimePerformanceAlarmListener } from '../../service/realtime/RealtimePerformanceAlarm';

/** An interface for transmission quality policy, network events, and performance alarms. */
export interface QualityControlling {

  /** Sets the uplink video statistics listener; null removes it. */
  setUplinkVideoStatisticsListener(
    listener: UplinkVideoStatisticsListener | null
  ): void;

  /** Sets the result stream video statistics listener; null removes it. */
  setDownlinkVideoStatisticsListener(
    listener: DownlinkVideoStatisticsListener | null
  ): void;

  /** The fixed media baseline and current transmission levels. */
  readonly qualityConfiguration: QualityConfiguration | undefined;

  /**
   * Initializes uplink/downlink adaptation from the media baseline and valid quality history.
   *
   * @param baseline The baseline preserving media aspect ratio and explicit encoding settings.
   * @param model The model name separating quality history by model.
   * @param minimumInputPixels The minimum uplink pixel area; defaults to zero.
   * @param isAdaptiveQualityEnabled Whether to restore quality history; false starts both at L1.
   *
   * @returns The initialized uplink/downlink quality configuration.
   */
  prepareQuality(
    baseline: RealtimeVideoFormat,
    model: string,
    minimumInputPixels?: number,
    isAdaptiveQualityEnabled?: boolean
  ): QualityConfiguration;

  /**
   * Replaces the media baseline while retaining quality levels and resetting sample windows.
   *
   * @param baseline The baseline preserving media aspect ratio and explicit encoding settings.
   *
   * @returns The updated configuration, or undefined before preparation.
   */
  rebaseQuality(
    baseline: RealtimeVideoFormat
  ): QualityConfiguration | undefined;

  /**
   * Sets the adaptive quality handler; null removes it.
   *
   * @param listener The event handler, or null to remove it.
   */
  setAdaptiveQualityListener(
    listener: AdaptiveQualityListener | null
  ): void;

  /**
   * Resolves quality recommendations from consecutive samples without changing current levels.
   *
   * @param quality The uplink, downlink, or combined network quality sample.
   * @param sampledAt The monotonic network sample time, in seconds.
   *
   * @returns The candidate levels, with undefined for directions not requiring adjustment.
   */
  proposeQuality(
    quality: RealtimeNetworkQuality,
    sampledAt: number
  ): QualityChange;

  /**
   * Records a quality submission, updating levels and history only on success.
   *
   * @param downlink Whether this is downlink; false selects uplink.
   * @param level The quality level, from 1 to 5; lower values mean higher quality.
   * @param success Whether the configuration was submitted successfully.
   */
  completeQuality(
    downlink: boolean,
    level: number,
    success: boolean
  ): void;

  /** Clears consecutive samples while retaining quality levels. */
  resetQualitySamples(): void;

  /** Releases quality state and history references and removes the adaptive listener. */
  resetQuality(): void;

  /**
   * Enables uplink statistics and notifies listeners to clear previous values.
   *
   * @param enabled Whether to enable this capability.
   */
  setUplinkVideoStatisticsEnabled(
    enabled: boolean
  ): void;

  /**
   * Selects the observed remote user and notifies listeners to clear previous values.
   *
   * @param userId The remote user to observe; undefined stops downlink statistics delivery.
   */
  setDownlinkVideoStatisticsUser(
    userId: string | undefined
  ): void;

  /**
   * Sets the network quality listener.
   *
   * @param listener The network quality handler, or null to remove it.
   */
  setNetworkQualityListener(
    listener: RealtimeNetworkQualityListener | null
  ): void;

  /**
   * Sets the performance alarm listener.
   *
   * @param listener The performance alarm handler, or null to remove it.
   */
  setPerformanceAlarmListener(
    listener: RealtimePerformanceAlarmListener | null
  ): void;
}
