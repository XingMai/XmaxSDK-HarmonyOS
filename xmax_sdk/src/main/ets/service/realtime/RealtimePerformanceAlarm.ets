//
//  RealtimePerformanceAlarm.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { RealtimeVideoFormat } from './RealtimeVideoFormat';

/** The device performance status: normal or limited. */
export enum RealtimePerformanceStatus {

  /** Device performance is limited. */
  LIMITED = 'Limited',

  /** Device performance has recovered. */
  RECOVERED = 'Recovered'
}

/** Device performance state and the recommended RTC video format. */
export class RealtimePerformanceAlarm {

  /** The server session status. */
  readonly status: RealtimePerformanceStatus;

  /** The video format recommended by a device performance alarm. */
  readonly suggestedVideoFormat?: RealtimeVideoFormat;

  /** Creates a device performance alarm. */
  constructor(
    status: RealtimePerformanceStatus,
    suggestedVideoFormat?: RealtimeVideoFormat
  ) {
    this.status = status;
    this.suggestedVideoFormat = suggestedVideoFormat;
  }
}

/**
 * Receives device performance alarms and recommended formats.
 *
 * @param alarm The performance status and recommended video format.
 */
export type RealtimePerformanceAlarmListener = (
  alarm: RealtimePerformanceAlarm
) => void;
