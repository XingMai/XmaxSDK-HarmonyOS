import { RealtimeVideoFormat } from './RealtimeVideoFormat';

export enum RealtimePerformanceStatus {
  LIMITED = 'Limited',
  RECOVERED = 'Recovered'
}

export class RealtimePerformanceAlarm {
  readonly status: RealtimePerformanceStatus;
  readonly suggestedVideoFormat?: RealtimeVideoFormat;

  constructor(
    status: RealtimePerformanceStatus,
    suggestedVideoFormat?: RealtimeVideoFormat
  ) {
    this.status = status;
    this.suggestedVideoFormat = suggestedVideoFormat;
  }
}

export type RealtimePerformanceAlarmListener = (alarm: RealtimePerformanceAlarm) => void;
