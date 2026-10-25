//
//  QualityController.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { UplinkVideoStatistics, DownlinkVideoStatistics, UplinkVideoStatisticsListener, DownlinkVideoStatisticsListener } from '../../foundation/rtc/VideoStatistics';
import { QualityClock } from './QualityClock';
import { QualityConfiguration, QualityChange, AdaptiveQualityListener } from './QualityConfiguration';
import { QualityDirection } from './QualityDirection';
import { QualityHistory, QualityHistoryStore, MemoryQualityHistoryStore } from './QualityHistory';
import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import { RtcManaging } from '../../foundation/rtc/RtcManaging';
import {
  RtcQualityLevel,
  RtcQualityListener
} from '../../foundation/rtc/RtcQualityListener';
import {
  RealtimeNetworkQuality,
  RealtimeNetworkQualityLevel,
  RealtimeNetworkQualityListener
} from '../../service/realtime/RealtimeNetworkQuality';
import {
  RealtimePerformanceAlarm,
  RealtimePerformanceAlarmListener,
  RealtimePerformanceStatus
} from '../../service/realtime/RealtimePerformanceAlarm';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import { QualityControlling } from './QualityControlling';

/** Manages quality levels, history, and RTC events with independent application notifications. */
export class QualityController implements QualityControlling, RtcQualityListener {

  // Uplink and downlink statistics listeners

  /** The handler for published uplink video statistics. */
  private uplinkStatisticsListener: UplinkVideoStatisticsListener | null = null;

  /** The current result-stream statistics handler. */
  private downlinkStatisticsListener: DownlinkVideoStatisticsListener | null = null;

  // Statistics publication state and remote user

  /** Whether current publication enables uplink statistics delivery. */
  private uplinkStatisticsEnabled: boolean = false;

  /** The result user selected for downlink statistics. */
  private downlinkStatisticsUser: string | undefined;

  // Asynchronous statistics delivery revision

  /** The revision rejecting obsolete uplink statistics. */
  private uplinkStatisticsVersion: number = 0;

  /** The revision rejecting obsolete downlink statistics delivery. */
  private downlinkStatisticsVersion: number = 0;

  /** Replaces the uplink statistics listener and invalidates queued notifications. */
  setUplinkVideoStatisticsListener(
    listener: UplinkVideoStatisticsListener | null
  ): void {
    this.uplinkStatisticsVersion++;
    this.uplinkStatisticsListener = listener;
  }

  /** Replaces the downlink statistics listener and invalidates queued notifications. */
  setDownlinkVideoStatisticsListener(
    listener: DownlinkVideoStatisticsListener | null
  ): void {
    this.downlinkStatisticsVersion++;
    this.downlinkStatisticsListener = listener;
  }

  /**
   * Enables uplink statistics and notifies listeners to clear previous values.
   *
   * @param enabled Whether to enable this capability.
   */
  setUplinkVideoStatisticsEnabled(
    enabled: boolean
  ): void {
    this.uplinkStatisticsEnabled = enabled;
    this.deliverUplink(
      undefined,
      ++this.uplinkStatisticsVersion
    );
  }

  /**
   * Selects the observed remote user and notifies listeners to clear previous values.
   *
   * @param userId The remote user to observe; undefined stops downlink statistics delivery.
   */
  setDownlinkVideoStatisticsUser(
    userId: string | undefined
  ): void {
    this.downlinkStatisticsUser = userId;
    this.deliverDownlink(
      undefined,
      ++this.downlinkStatisticsVersion
    );
  }

  /**
   * Receives current uplink statistics for logs or application listeners.
   *
   * @param statistics The published uplink video statistics.
   */
  onUplinkVideoStatistics(
    statistics: UplinkVideoStatistics
  ): void {
    if (this.uplinkStatisticsEnabled) {
      this.deliverUplink(
        statistics,
        this.uplinkStatisticsVersion
      );
    }
  }

  /**
   * Receives a remote user's downlink video statistics.
   *
   * @param statistics The remote user's downlink video statistics.
   */
  onDownlinkVideoStatistics(
    statistics: DownlinkVideoStatistics
  ): void {
    if (statistics.userId === this.downlinkStatisticsUser) {
      this.deliverDownlink(
        statistics,
        this.downlinkStatisticsVersion
      );
    }
  }

  /**
   * Delivers current-revision uplink statistics, rejecting events after listener or publication
   * changes.
   *
   * @param statistics The normalized statistics, or undefined to clear prior values.
   * @param version The revision rejecting obsolete asynchronous notifications.
   */
  private deliverUplink(
    statistics: UplinkVideoStatistics | undefined,
    version: number
  ): void {
    if (this.uplinkStatisticsListener === null) { return; }
    void Promise.resolve().then((): void => {
      if (version !== this.uplinkStatisticsVersion || (statistics !== undefined && !this.uplinkStatisticsEnabled)) { return; }
      try { this.uplinkStatisticsListener?.(statistics); }
      catch (error) {
        XmaxLogger.error(
          'Uplink statistics listener failed: ' + String(error),
          'Quality'
        );
      }
    });
  }

  /**
   * Delivers current-user, current-revision downlink statistics, rejecting obsolete events.
   *
   * @param statistics The normalized statistics, or undefined to clear prior values.
   * @param version The revision rejecting obsolete asynchronous notifications.
   */
  private deliverDownlink(
    statistics: DownlinkVideoStatistics | undefined,
    version: number
  ): void {
    if (this.downlinkStatisticsListener === null) { return; }
    void Promise.resolve().then((): void => {
      if (version !== this.downlinkStatisticsVersion ||
        (statistics !== undefined && statistics.userId !== this.downlinkStatisticsUser)) { return; }
      try { this.downlinkStatisticsListener?.(statistics); }
      catch (error) {
        XmaxLogger.error(
          'Downlink statistics listener failed: ' + String(error),
          'Quality'
        );
      }
    });
  }

  // Quality history storage dependency

  /** The numeric store backing adaptive quality history. */
  private readonly historyStore: QualityHistoryStore;

  // Per-direction quality state and history

  /** The adaptive state for uplink transmission. */
  private uplinkQuality: QualityDirection | undefined;

  /** The adaptive state for downlink transmission. */
  private downlinkQuality: QualityDirection | undefined;

  /** The model-specific record of successfully applied quality levels. */
  private history: QualityHistory | undefined;

  // Adaptive quality notification

  /** The handler scheduling adaptive changes from quality samples. */
  private adaptiveListener: AdaptiveQualityListener | null = null;

  /** The current media baseline and transmission levels, or undefined before preparation. */
  get qualityConfiguration(): QualityConfiguration | undefined {
    return this.uplinkQuality === undefined || this.downlinkQuality === undefined ? undefined :
      new QualityConfiguration(
        this.uplinkQuality.baseline,
        this.uplinkQuality.level,
        this.downlinkQuality.level,
        this.uplinkQuality.minimumInputPixels
      );
  }

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
    minimumInputPixels: number = 0,
    isAdaptiveQualityEnabled: boolean = true
  ): QualityConfiguration {
    baseline.validate();
    this.history = isAdaptiveQualityEnabled ? new QualityHistory(
      model,
      this.historyStore
    ) : undefined;
    this.uplinkQuality = new QualityDirection(
      baseline,
      this.history?.read(false) ?? 1,
      false,
      minimumInputPixels
    );
    this.downlinkQuality = new QualityDirection(
      baseline,
      this.history?.read(true) ?? 1,
      true,
      minimumInputPixels
    );
    return new QualityConfiguration(
      baseline,
      this.uplinkQuality.level,
      this.downlinkQuality.level,
      minimumInputPixels
    );
  }

  /**
   * Replaces the media baseline while retaining quality levels and resetting sample windows.
   *
   * @param baseline The baseline preserving media aspect ratio and explicit encoding settings.
   *
   * @returns The updated configuration, or undefined before preparation.
   */
  rebaseQuality(
    baseline: RealtimeVideoFormat
  ): QualityConfiguration | undefined {
    const configuration: QualityConfiguration | undefined = this.qualityConfiguration;
    if (configuration === undefined) { return undefined; }
    this.uplinkQuality = new QualityDirection(
      baseline,
      configuration.uplinkLevel,
      false,
      configuration.minimumInputPixels
    );
    this.downlinkQuality = new QualityDirection(
      baseline,
      configuration.downlinkLevel,
      true,
      configuration.minimumInputPixels
    );
    return this.qualityConfiguration;
  }

  /**
   * Sets the adaptive quality handler; null removes it.
   *
   * @param listener The event handler, or null to remove it.
   */
  setAdaptiveQualityListener(
    listener: AdaptiveQualityListener | null
  ): void {
    this.adaptiveListener = listener;
  }

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
  ): QualityChange {
    const now: number = QualityClock.now();
    return new QualityChange(
      this.uplinkQuality?.observe(
        quality.uplink,
        sampledAt,
        now
      ),
      this.downlinkQuality?.observe(
        quality.downlink,
        sampledAt,
        now
      )
    );
  }

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
  ): void {
    const direction: QualityDirection | undefined = downlink ? this.downlinkQuality : this.uplinkQuality;
    if (direction === undefined) { return; }
    direction.complete(
      level,
      success,
      QualityClock.now()
    );
    if (success) {
      this.history?.write(
        direction.level,
        downlink
      );
    }
  }

  /** Clears consecutive samples while retaining quality levels. */
  resetQualitySamples(): void {
    this.uplinkQuality?.resetSamples();
    this.downlinkQuality?.resetSamples();
  }

  /** Releases quality state and history references and removes the adaptive listener. */
  resetQuality(): void {
    this.uplinkQuality = undefined;
    this.downlinkQuality = undefined;
    this.history = undefined;
    this.adaptiveListener = null;
  }

  // Network quality and performance notifications

  /** The handler receiving normalized network quality. */
  private networkQualityListener: RealtimeNetworkQualityListener | null = null;

  /** The device performance alarm handler. */
  private performanceAlarmListener: RealtimePerformanceAlarmListener | null = null;

  /**
   * Creates a quality controller.
   *
   * @param rtcManager The RTC manager providing quality events.
   * @param historyStore The numeric history store, defaulting to memory.
   */
  constructor(
    rtcManager: RtcManaging,
    historyStore: QualityHistoryStore = new MemoryQualityHistoryStore()
  ) {
    this.historyStore = historyStore;
    rtcManager.setQualityListener(this);
  }

  /**
   * Sets the network quality listener.
   *
   * @param listener The network quality handler, or null to remove it.
   */
  setNetworkQualityListener(
    listener: RealtimeNetworkQualityListener | null
  ): void {
    this.networkQualityListener = listener;
  }

  /**
   * Sets the device performance listener.
   *
   * @param listener The performance alarm handler, or null to remove it.
   */
  setPerformanceAlarmListener(
    listener: RealtimePerformanceAlarmListener | null
  ): void {
    this.performanceAlarmListener = listener;
  }

  /**
   * Receives and normalizes uplink/downlink RTC quality events.
   *
   * @param uplink The local uplink quality level.
   * @param downlink The local downlink quality level.
   */
  onNetworkQuality(
    uplink: RtcQualityLevel,
    downlink: RtcQualityLevel
  ): void {
    const listener: RealtimeNetworkQualityListener | null =
      this.networkQualityListener;
    const quality: RealtimeNetworkQuality = new RealtimeNetworkQuality(
      QualityController.networkQualityLevel(uplink),
      QualityController.networkQualityLevel(downlink)
    );

    try {
      this.adaptiveListener?.(
        quality,
        QualityClock.now()
      );
    } catch (error) {
      XmaxLogger.warn(
        'Adaptive quality listener failed: ' + String(error),
        'Quality'
      );
    }
    try {
      listener?.(quality);
    } catch (error) {
      const reason: string = error instanceof Error ? error.message : String(error);
      XmaxLogger.error(
        `${XmaxLogger.localized("网络质量监听器执行失败 (Network Quality Listener Failed)\n└─ 原因：", "网络质量监听器执行失败 (Network Quality Listener Failed)\n└─ Reason: ")}${reason}`,
        'Realtime'
      );
    }
  }

  /**
   * Converts RTC performance alarms and recommended video formats.
   *
   * @param limited Whether device performance is limited.
   * @param suggestedWidth The recommended video width.
   * @param suggestedHeight The recommended video height.
   * @param suggestedFrameRate The recommended video frame rate.
   */
  onPerformanceAlarm(
    limited: boolean,
    suggestedWidth: number,
    suggestedHeight: number,
    suggestedFrameRate: number
  ): void {
    const listener: RealtimePerformanceAlarmListener | null =
      this.performanceAlarmListener;
    if (listener === null) {
      return;
    }

    const status: RealtimePerformanceStatus = limited ?
      RealtimePerformanceStatus.LIMITED : RealtimePerformanceStatus.RECOVERED;
    const alarm: RealtimePerformanceAlarm = new RealtimePerformanceAlarm(
      status,
      QualityController.suggestedVideoFormat(
        suggestedWidth,
        suggestedHeight,
        suggestedFrameRate
      )
    );

    try {
      listener(alarm);
    } catch (error) {
      const reason: string = error instanceof Error ? error.message : String(error);
      XmaxLogger.error(
        `${XmaxLogger.localized("性能告警监听器执行失败 (Performance Alarm Listener Failed)\n└─ 原因：", "性能告警监听器执行失败 (Performance Alarm Listener Failed)\n└─ Reason: ")}${reason}`,
        'Realtime'
      );
    }
  }

  /**
   * Maps an RTC network quality level into a public service level.
   *
   * @param level The RTC network quality level.
   *
   * @returns The corresponding realtime network quality level.
   */
  private static networkQualityLevel(
    level: RtcQualityLevel
  ): RealtimeNetworkQualityLevel {
    switch (level) {
      case RtcQualityLevel.EXCELLENT:
        return RealtimeNetworkQualityLevel.EXCELLENT;
      case RtcQualityLevel.GOOD:
        return RealtimeNetworkQualityLevel.GOOD;
      case RtcQualityLevel.POOR:
        return RealtimeNetworkQualityLevel.POOR;
      case RtcQualityLevel.BAD:
        return RealtimeNetworkQualityLevel.BAD;
      case RtcQualityLevel.VERY_BAD:
        return RealtimeNetworkQualityLevel.VERY_BAD;
      case RtcQualityLevel.DOWN:
        return RealtimeNetworkQualityLevel.DOWN;
      default:
        return RealtimeNetworkQualityLevel.UNKNOWN;
    }
  }

  /**
   * Creates a valid video format from RTC recommendations.
   *
   * @param width The recommended video width.
   * @param height The recommended video height.
   * @param frameRate The recommended video frame rate.
   *
   * @returns The video format, or undefined for invalid recommendations.
   */
  private static suggestedVideoFormat(
    width: number,
    height: number,
    frameRate: number
  ): RealtimeVideoFormat | undefined {
    if (!QualityController.isPositiveNumber(width) ||
      !QualityController.isPositiveNumber(height) ||
      !QualityController.isPositiveNumber(frameRate)) {
      return undefined;
    }

    return new RealtimeVideoFormat(
      width,
      height,
      frameRate
    );
  }

  /**
   * Checks whether a value is finite and positive.
   *
   * @param value The value to check.
   *
   * @returns True for a finite positive value.
   */
  private static isPositiveNumber(
    value: number
  ): boolean {
    return typeof value === 'number' && Number.isFinite(value) && value > 0;
  }
}
