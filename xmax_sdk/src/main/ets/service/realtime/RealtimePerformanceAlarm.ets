//
//  RealtimePerformanceAlarm.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { RealtimeVideoFormat } from './RealtimeVideoFormat';

/** 标识设备性能正常或已受限。 */
export enum RealtimePerformanceStatus {
  LIMITED = 'Limited',
  RECOVERED = 'Recovered'
}

/** 提供设备性能状态及 RTC 建议采用的视频格式。 */
export class RealtimePerformanceAlarm {

  /** 设备性能状态与建议规格 */
  readonly status: RealtimePerformanceStatus;
  readonly suggestedVideoFormat?: RealtimeVideoFormat;

  /**
   * 创建设备性能告警。
   *
   * @param status 会话状态或设备性能状态。
   * @param suggestedVideoFormat 设备性能告警建议使用的视频格式；不可用时可省略。
   * @returns 新建的 RealtimePerformanceAlarm 实例。
   */
  constructor(
    status: RealtimePerformanceStatus,
    suggestedVideoFormat?: RealtimeVideoFormat
  ) {
    this.status = status;
    this.suggestedVideoFormat = suggestedVideoFormat;
  }
}

/**
 * 接收设备性能告警与建议格式的回调。
 *
 * @param alarm 包含性能状态和建议视频格式的告警。
 * @returns 无返回值。
 */
export type RealtimePerformanceAlarmListener = (alarm: RealtimePerformanceAlarm) => void;
