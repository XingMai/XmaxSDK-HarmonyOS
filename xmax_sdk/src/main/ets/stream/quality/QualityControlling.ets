import { UplinkVideoStatisticsListener, DownlinkVideoStatisticsListener } from '../../foundation/rtc/VideoStatistics';
import { QualityConfiguration, QualityChange, AdaptiveQualityListener } from './QualityConfiguration';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import { RealtimeNetworkQuality } from '../../service/realtime/RealtimeNetworkQuality';
import { RealtimeNetworkQualityListener } from '../../service/realtime/RealtimeNetworkQuality';
import { RealtimePerformanceAlarmListener } from '../../service/realtime/RealtimePerformanceAlarm';

/** 定义传输档位策略、网络质量与设备性能告警监听能力。 */
export interface QualityControlling {
  /** 设置上行统计监听；null 移除。停止发布或断开时收到 undefined。 */
  setUplinkVideoStatisticsListener(listener: UplinkVideoStatisticsListener | null): void;
  /** 设置下行统计监听；null 移除。仅交付当前生成流，流清理时收到 undefined。 */
  setDownlinkVideoStatisticsListener(listener: DownlinkVideoStatisticsListener | null): void;

  readonly qualityConfiguration: QualityConfiguration | undefined;
  prepareQuality(baseline: RealtimeVideoFormat, model: string): QualityConfiguration;
  rebaseQuality(baseline: RealtimeVideoFormat): QualityConfiguration | undefined;
  setAdaptiveQualityListener(listener: AdaptiveQualityListener | null): void;
  proposeQuality(quality: RealtimeNetworkQuality, sampledAt: number): QualityChange;
  completeQuality(downlink: boolean, level: number, success: boolean): void;
  resetQualitySamples(): void;
  resetQuality(): void;
  setUplinkVideoStatisticsEnabled(enabled: boolean): void;
  setDownlinkVideoStatisticsUser(userId: string | undefined): void;


  /**
   * 设置网络质量监听器。
   *
   * @param listener 网络质量监听器；传入空值时清除监听器。
   * @returns 无返回值。
   */
  setNetworkQualityListener(
    listener: RealtimeNetworkQualityListener | null
  ): void;

  /**
   * 设置性能告警监听器。
   *
   * @param listener 性能告警监听器；传入空值时清除监听器。
   * @returns 无返回值。
   */
  setPerformanceAlarmListener(
    listener: RealtimePerformanceAlarmListener | null
  ): void;
}
