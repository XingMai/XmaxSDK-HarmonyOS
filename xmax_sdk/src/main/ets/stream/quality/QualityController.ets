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

/** 管理上下行传输档位、历史和 RTC 质量事件，独立通知业务监听器。 */
export class QualityController implements QualityControlling, RtcQualityListener {

  private uplinkStatisticsListener: UplinkVideoStatisticsListener | null = null;
  private downlinkStatisticsListener: DownlinkVideoStatisticsListener | null = null;
  private uplinkStatisticsEnabled: boolean = false;
  private downlinkStatisticsUser: string | undefined;
  private uplinkStatisticsVersion: number = 0;
  private downlinkStatisticsVersion: number = 0;

  setUplinkVideoStatisticsListener(listener: UplinkVideoStatisticsListener | null): void {
    this.uplinkStatisticsVersion++;
    this.uplinkStatisticsListener = listener;
  }
  setDownlinkVideoStatisticsListener(listener: DownlinkVideoStatisticsListener | null): void {
    this.downlinkStatisticsVersion++;
    this.downlinkStatisticsListener = listener;
  }
  setUplinkVideoStatisticsEnabled(enabled: boolean): void {
    this.uplinkStatisticsEnabled = enabled;
    this.deliverUplink(undefined, ++this.uplinkStatisticsVersion);
  }
  setDownlinkVideoStatisticsUser(userId: string | undefined): void {
    this.downlinkStatisticsUser = userId;
    this.deliverDownlink(undefined, ++this.downlinkStatisticsVersion);
  }
  onUplinkVideoStatistics(statistics: UplinkVideoStatistics): void {
    if (this.uplinkStatisticsEnabled) { this.deliverUplink(statistics, this.uplinkStatisticsVersion); }
  }
  onDownlinkVideoStatistics(statistics: DownlinkVideoStatistics): void {
    if (statistics.userId === this.downlinkStatisticsUser) { this.deliverDownlink(statistics, this.downlinkStatisticsVersion); }
  }
  private deliverUplink(statistics: UplinkVideoStatistics | undefined, version: number): void {
    if (this.uplinkStatisticsListener === null) { return; }
    void Promise.resolve().then((): void => {
      if (version !== this.uplinkStatisticsVersion || (statistics !== undefined && !this.uplinkStatisticsEnabled)) { return; }
      try { this.uplinkStatisticsListener?.(statistics); }
      catch (error) { XmaxLogger.error('Uplink statistics listener failed: ' + String(error), 'Quality'); }
    });
  }
  private deliverDownlink(statistics: DownlinkVideoStatistics | undefined, version: number): void {
    if (this.downlinkStatisticsListener === null) { return; }
    void Promise.resolve().then((): void => {
      if (version !== this.downlinkStatisticsVersion ||
        (statistics !== undefined && statistics.userId !== this.downlinkStatisticsUser)) { return; }
      try { this.downlinkStatisticsListener?.(statistics); }
      catch (error) { XmaxLogger.error('Downlink statistics listener failed: ' + String(error), 'Quality'); }
    });
  }

  private readonly historyStore: QualityHistoryStore;
  private uplinkQuality: QualityDirection | undefined;
  private downlinkQuality: QualityDirection | undefined;
  private history: QualityHistory | undefined;
  private adaptiveListener: AdaptiveQualityListener | null = null;

  get qualityConfiguration(): QualityConfiguration | undefined {
    return this.uplinkQuality === undefined || this.downlinkQuality === undefined ? undefined :
      new QualityConfiguration(this.uplinkQuality.baseline, this.uplinkQuality.level, this.downlinkQuality.level);
  }
  prepareQuality(baseline: RealtimeVideoFormat, model: string): QualityConfiguration {
    baseline.validate();
    this.history = new QualityHistory(model, this.historyStore);
    this.uplinkQuality = new QualityDirection(baseline, this.history.read(false), false);
    this.downlinkQuality = new QualityDirection(baseline, this.history.read(true), true);
    return new QualityConfiguration(baseline, this.uplinkQuality.level, this.downlinkQuality.level);
  }
  rebaseQuality(baseline: RealtimeVideoFormat): QualityConfiguration | undefined {
    const configuration: QualityConfiguration | undefined = this.qualityConfiguration;
    if (configuration === undefined) { return undefined; }
    this.uplinkQuality = new QualityDirection(baseline, configuration.uplinkLevel, false);
    this.downlinkQuality = new QualityDirection(baseline, configuration.downlinkLevel, true);
    return this.qualityConfiguration;
  }
  setAdaptiveQualityListener(listener: AdaptiveQualityListener | null): void { this.adaptiveListener = listener; }
  proposeQuality(quality: RealtimeNetworkQuality, sampledAt: number): QualityChange {
    const now: number = QualityClock.now();
    return new QualityChange(this.uplinkQuality?.observe(quality.uplink, sampledAt, now),
      this.downlinkQuality?.observe(quality.downlink, sampledAt, now));
  }
  completeQuality(downlink: boolean, level: number, success: boolean): void {
    const direction: QualityDirection | undefined = downlink ? this.downlinkQuality : this.uplinkQuality;
    if (direction === undefined) { return; }
    direction.complete(level, success, QualityClock.now());
    if (success) { this.history?.write(direction.level, downlink); }
  }
  resetQualitySamples(): void {
    this.uplinkQuality?.resetSamples();
    this.downlinkQuality?.resetSamples();
  }
  resetQuality(): void {
    this.uplinkQuality = undefined;
    this.downlinkQuality = undefined;
    this.history = undefined;
    this.adaptiveListener = null;
  }

  // 事件监听
  private networkQualityListener: RealtimeNetworkQualityListener | null = null;
  private performanceAlarmListener: RealtimePerformanceAlarmListener | null = null;

  /**
   * 创建质量监控 Controller。
   *
   * @param rtcManager 提供质量事件的 RTC Manager。
   */
  constructor(rtcManager: RtcManaging, historyStore: QualityHistoryStore = new MemoryQualityHistoryStore()) {
    this.historyStore = historyStore;
    rtcManager.setQualityListener(this);
  }

  /**
   * 设置网络质量监听器。
   *
   * @param listener 网络质量监听器；传入空值时清除监听器。
   * @returns 无返回值。
   */
  setNetworkQualityListener(listener: RealtimeNetworkQualityListener | null): void {
    this.networkQualityListener = listener;
  }

  /**
   * 设置设备性能告警监听器。
   *
   * @param listener 性能告警监听器；传入空值时清除监听器。
   * @returns 无返回值。
   */
  setPerformanceAlarmListener(listener: RealtimePerformanceAlarmListener | null): void {
    this.performanceAlarmListener = listener;
  }

  /**
   * 接收并转换 RTC 上下行网络质量事件。
   *
   * @param uplink 本地上行网络质量。
   * @param downlink 本地下行网络质量。
   * @returns 无返回值。
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
      this.adaptiveListener?.(quality, QualityClock.now());
    } catch (error) {
      XmaxLogger.warn('Adaptive quality listener failed: ' + String(error), 'Quality');
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
   * 接收 RTC 性能告警并转换建议的视频格式。
   *
   * @param limited 当前设备性能是否受限。
   * @param suggestedWidth 建议的视频宽度。
   * @param suggestedHeight 建议的视频高度。
   * @param suggestedFrameRate 建议的视频帧率。
   * @returns 无返回值。
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
   * 将 RTC 网络质量等级转换为服务层公开等级。
   *
   * @param level RTC 网络质量等级。
   * @returns 对应的实时生成网络质量等级。
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
   * 根据 RTC 建议参数创建可用的视频格式。
   *
   * @param width 建议的视频宽度。
   * @param height 建议的视频高度。
   * @param frameRate 建议的视频帧率。
   * @returns 参数有效时返回视频格式，否则返回空值。
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

    return new RealtimeVideoFormat(width, height, frameRate);
  }

  /**
   * 判断数值是否为有限正数。
   *
   * @param value 待检查数值。
   * @returns 数值为有限正数时返回 true，否则返回 false。
   */
  private static isPositiveNumber(value: number): boolean {
    return typeof value === 'number' && Number.isFinite(value) && value > 0;
  }
}
