//
//  QualityControlling.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { UplinkVideoStatisticsListener, DownlinkVideoStatisticsListener } from '../../foundation/rtc/VideoStatistics';
import { QualityConfiguration, QualityChange, AdaptiveQualityListener } from './QualityConfiguration';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import { RealtimeNetworkQuality } from '../../service/realtime/RealtimeNetworkQuality';
import { RealtimeNetworkQualityListener } from '../../service/realtime/RealtimeNetworkQuality';
import { RealtimePerformanceAlarmListener } from '../../service/realtime/RealtimePerformanceAlarm';

/** 定义传输档位策略、网络质量与设备性能告警监听能力。 */
export interface QualityControlling {
  /**
   * 设置上行视频统计监听器；传入 null 清除，停止发布或断开时以 undefined 清空统计。
   *
   * @param listener 异步接收上行统计或 undefined 清空通知的监听器；null 表示移除。
   * @returns 无返回值。
   */
  setUplinkVideoStatisticsListener(listener: UplinkVideoStatisticsListener | null): void;

  /**
   * 设置当前生成流的下行视频统计监听器；传入 null 清除，流清理时以 undefined 清空统计。
   *
   * @param listener 异步接收当前生成流下行统计或 undefined 清空通知的监听器；null 表示移除。
   * @returns 无返回值。
   */
  setDownlinkVideoStatisticsListener(listener: DownlinkVideoStatisticsListener | null): void;

  /** 自动传输档位状态 */
  readonly qualityConfiguration: QualityConfiguration | undefined;

  /**
   * 根据媒体基准和有效历史档位初始化上下行自动调档。
   *
   * @param baseline 保持原始媒体比例与用户编码选项的视频格式基准。
   * @param model 生成模型名称，用于隔离各模型的历史档位。
   * @returns 初始化后的上下行档位配置。
   */
  prepareQuality(baseline: RealtimeVideoFormat, model: string): QualityConfiguration;

  /**
   * 保留上下行档位并替换媒体基准，重置各方向的采样窗口。
   *
   * @param baseline 保持原始媒体比例与用户编码选项的视频格式基准。
   * @returns 更新后的配置；尚未准备时返回 undefined。
   */
  rebaseQuality(baseline: RealtimeVideoFormat): QualityConfiguration | undefined;

  /**
   * 设置自动调档事件监听器；传入 null 清除监听器。
   *
   * @param listener 接收事件的监听器；可空接口传入 null 时清除监听器。
   * @returns 无返回值。
   */
  setAdaptiveQualityListener(listener: AdaptiveQualityListener | null): void;

  /**
   * 根据连续网络采样计算上下行建议档位，不直接修改当前档位。
   *
   * @param quality 当前方向或上下行的网络质量采样。
   * @param sampledAt 网络采样的单调时间，单位秒。
   * @returns 各方向的候选档位；无调整建议的方向为 undefined。
   */
  proposeQuality(quality: RealtimeNetworkQuality, sampledAt: number): QualityChange;

  /**
   * 记录一次调档提交的结果，仅成功时更新档位和历史。
   *
   * @param downlink 是否为下行方向；false 表示上行。
   * @param level 传输档位，范围 1～5，数值越小质量越高。
   * @param success 此次配置是否已成功提交。
   * @returns 无返回值。
   */
  completeQuality(downlink: boolean, level: number, success: boolean): void;

  /**
   * 清空上下行连续采样计数，保留当前档位。
   *
   * @returns 无返回值。
   */
  resetQualitySamples(): void;

  /**
   * 释放上下行调档状态与历史引用，清除自动调档监听器。
   *
   * @returns 无返回值。
   */
  resetQuality(): void;

  /**
   * 开启或关闭上行统计交付，并通知监听器清空旧统计。
   *
   * @param enabled 是否开启该能力。
   * @returns 无返回值。
   */
  setUplinkVideoStatisticsEnabled(enabled: boolean): void;

  /**
   * 切换需要交付统计的远端用户，并通知监听器清空旧统计。
   *
   * @param userId 需要监听的远端用户标识；undefined 表示停止交付下行统计。
   * @returns 无返回值。
   */
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
