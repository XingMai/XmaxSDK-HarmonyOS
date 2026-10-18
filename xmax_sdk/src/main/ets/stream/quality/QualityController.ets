//
//  QualityController.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
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

/** 管理上下行传输档位、历史和 RTC 质量事件，独立通知业务监听器。 */
export class QualityController implements QualityControlling, RtcQualityListener {

  /** 上下行统计监听器 */
  private uplinkStatisticsListener: UplinkVideoStatisticsListener | null = null;
  private downlinkStatisticsListener: DownlinkVideoStatisticsListener | null = null;

  /** 统计交付的发布状态与远端用户 */
  private uplinkStatisticsEnabled: boolean = false;
  private downlinkStatisticsUser: string | undefined;

  /** 异步统计通知版本 */
  private uplinkStatisticsVersion: number = 0;
  private downlinkStatisticsVersion: number = 0;

  /**
   * 设置上行视频统计监听器；传入 null 清除，停止发布或断开时以 undefined 清空统计。
   *
   * @param listener 异步接收上行统计或 undefined 清空通知的监听器；null 表示移除。
   * @returns 无返回值。
   */
  setUplinkVideoStatisticsListener(listener: UplinkVideoStatisticsListener | null): void {
    this.uplinkStatisticsVersion++;
    this.uplinkStatisticsListener = listener;
  }

  /**
   * 设置当前生成流的下行视频统计监听器；传入 null 清除，流清理时以 undefined 清空统计。
   *
   * @param listener 异步接收当前生成流下行统计或 undefined 清空通知的监听器；null 表示移除。
   * @returns 无返回值。
   */
  setDownlinkVideoStatisticsListener(listener: DownlinkVideoStatisticsListener | null): void {
    this.downlinkStatisticsVersion++;
    this.downlinkStatisticsListener = listener;
  }

  /**
   * 开启或关闭上行统计交付，并通知监听器清空旧统计。
   *
   * @param enabled 是否开启该能力。
   * @returns 无返回值。
   */
  setUplinkVideoStatisticsEnabled(enabled: boolean): void {
    this.uplinkStatisticsEnabled = enabled;
    this.deliverUplink(undefined, ++this.uplinkStatisticsVersion);
  }

  /**
   * 切换需要交付统计的远端用户，并通知监听器清空旧统计。
   *
   * @param userId 需要监听的远端用户标识；undefined 表示停止交付下行统计。
   * @returns 无返回值。
   */
  setDownlinkVideoStatisticsUser(userId: string | undefined): void {
    this.downlinkStatisticsUser = userId;
    this.deliverDownlink(undefined, ++this.downlinkStatisticsVersion);
  }

  /**
   * 接收 RTC 当前上行视频统计，供日志或业务监听使用。
   *
   * @param statistics 当前发布的上行视频统计。
   * @returns 无返回值。
   */
  onUplinkVideoStatistics(statistics: UplinkVideoStatistics): void {
    if (this.uplinkStatisticsEnabled) { this.deliverUplink(statistics, this.uplinkStatisticsVersion); }
  }

  /**
   * 接收 RTC 指定远端用户的下行视频统计。
   *
   * @param statistics 对应远端用户的下行视频统计。
   * @returns 无返回值。
   */
  onDownlinkVideoStatistics(statistics: DownlinkVideoStatistics): void {
    if (statistics.userId === this.downlinkStatisticsUser) { this.deliverDownlink(statistics, this.downlinkStatisticsVersion); }
  }

  /**
   * 异步交付当前版本的上行统计，丢弃监听器替换或流停用后的旧通知。
   *
   * @param statistics 统一视频统计；undefined 表示清除旧统计。
   * @param version 排除过期异步通知的版本号。
   * @returns 无返回值。
   */
  private deliverUplink(statistics: UplinkVideoStatistics | undefined, version: number): void {
    if (this.uplinkStatisticsListener === null) { return; }
    void Promise.resolve().then((): void => {
      if (version !== this.uplinkStatisticsVersion || (statistics !== undefined && !this.uplinkStatisticsEnabled)) { return; }
      try { this.uplinkStatisticsListener?.(statistics); }
      catch (error) { XmaxLogger.error('Uplink statistics listener failed: ' + String(error), 'Quality'); }
    });
  }

  /**
   * 异步交付当前用户与版本的下行统计，丢弃过期通知。
   *
   * @param statistics 统一视频统计；undefined 表示清除旧统计。
   * @param version 排除过期异步通知的版本号。
   * @returns 无返回值。
   */
  private deliverDownlink(statistics: DownlinkVideoStatistics | undefined, version: number): void {
    if (this.downlinkStatisticsListener === null) { return; }
    void Promise.resolve().then((): void => {
      if (version !== this.downlinkStatisticsVersion ||
        (statistics !== undefined && statistics.userId !== this.downlinkStatisticsUser)) { return; }
      try { this.downlinkStatisticsListener?.(statistics); }
      catch (error) { XmaxLogger.error('Downlink statistics listener failed: ' + String(error), 'Quality'); }
    });
  }

  /** 调档历史存储依赖 */
  private readonly historyStore: QualityHistoryStore;

  /** 各方向调档状态与历史 */
  private uplinkQuality: QualityDirection | undefined;
  private downlinkQuality: QualityDirection | undefined;
  private history: QualityHistory | undefined;

  /** 自动调档事件通知 */
  private adaptiveListener: AdaptiveQualityListener | null = null;

  /**
   * 读取当前上下行传输基准与档位。
   *
   * @returns 调档配置；尚未准备时返回 undefined。
   */
  get qualityConfiguration(): QualityConfiguration | undefined {
    return this.uplinkQuality === undefined || this.downlinkQuality === undefined ? undefined :
      new QualityConfiguration(this.uplinkQuality.baseline, this.uplinkQuality.level, this.downlinkQuality.level);
  }

  /**
   * 根据媒体基准和有效历史档位初始化上下行自动调档。
   *
   * @param baseline 保持原始媒体比例与用户编码选项的视频格式基准。
   * @param model 生成模型名称，用于隔离各模型的历史档位。
   * @returns 初始化后的上下行档位配置。
   */
  prepareQuality(baseline: RealtimeVideoFormat, model: string): QualityConfiguration {
    baseline.validate();
    this.history = new QualityHistory(model, this.historyStore);
    this.uplinkQuality = new QualityDirection(baseline, this.history.read(false), false);
    this.downlinkQuality = new QualityDirection(baseline, this.history.read(true), true);
    return new QualityConfiguration(baseline, this.uplinkQuality.level, this.downlinkQuality.level);
  }

  /**
   * 保留上下行档位并替换媒体基准，重置各方向的采样窗口。
   *
   * @param baseline 保持原始媒体比例与用户编码选项的视频格式基准。
   * @returns 更新后的配置；尚未准备时返回 undefined。
   */
  rebaseQuality(baseline: RealtimeVideoFormat): QualityConfiguration | undefined {
    const configuration: QualityConfiguration | undefined = this.qualityConfiguration;
    if (configuration === undefined) { return undefined; }
    this.uplinkQuality = new QualityDirection(baseline, configuration.uplinkLevel, false);
    this.downlinkQuality = new QualityDirection(baseline, configuration.downlinkLevel, true);
    return this.qualityConfiguration;
  }

  /**
   * 设置自动调档事件监听器；传入 null 清除监听器。
   *
   * @param listener 接收事件的监听器；可空接口传入 null 时清除监听器。
   * @returns 无返回值。
   */
  setAdaptiveQualityListener(listener: AdaptiveQualityListener | null): void { this.adaptiveListener = listener; }

  /**
   * 根据连续网络采样计算上下行建议档位，不直接修改当前档位。
   *
   * @param quality 当前方向或上下行的网络质量采样。
   * @param sampledAt 网络采样的单调时间，单位秒。
   * @returns 各方向的候选档位；无调整建议的方向为 undefined。
   */
  proposeQuality(quality: RealtimeNetworkQuality, sampledAt: number): QualityChange {
    const now: number = QualityClock.now();
    return new QualityChange(this.uplinkQuality?.observe(quality.uplink, sampledAt, now),
      this.downlinkQuality?.observe(quality.downlink, sampledAt, now));
  }

  /**
   * 记录一次调档提交的结果，仅成功时更新档位和历史。
   *
   * @param downlink 是否为下行方向；false 表示上行。
   * @param level 传输档位，范围 1～5，数值越小质量越高。
   * @param success 此次配置是否已成功提交。
   * @returns 无返回值。
   */
  completeQuality(downlink: boolean, level: number, success: boolean): void {
    const direction: QualityDirection | undefined = downlink ? this.downlinkQuality : this.uplinkQuality;
    if (direction === undefined) { return; }
    direction.complete(level, success, QualityClock.now());
    if (success) { this.history?.write(direction.level, downlink); }
  }

  /**
   * 清空上下行连续采样计数，保留当前档位。
   *
   * @returns 无返回值。
   */
  resetQualitySamples(): void {
    this.uplinkQuality?.resetSamples();
    this.downlinkQuality?.resetSamples();
  }

  /**
   * 释放上下行调档状态与历史引用，清除自动调档监听器。
   *
   * @returns 无返回值。
   */
  resetQuality(): void {
    this.uplinkQuality = undefined;
    this.downlinkQuality = undefined;
    this.history = undefined;
    this.adaptiveListener = null;
  }

  /** 网络质量与性能告警通知 */
  private networkQualityListener: RealtimeNetworkQualityListener | null = null;
  private performanceAlarmListener: RealtimePerformanceAlarmListener | null = null;

  /**
   * 创建质量监控 Controller。
   *
   * @param rtcManager 提供质量事件的 RTC Manager。
   * @param historyStore 保存自动调档历史的数值存储；默认使用内存。
   * @returns 新建的 QualityController 实例。
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
   * @param uplink 本地上行网络质量等级。
   * @param downlink 本地下行网络质量等级。
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
