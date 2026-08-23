export enum RealtimeNetworkQualityLevel {
  UNKNOWN = 'Unknown',
  EXCELLENT = 'Excellent',
  GOOD = 'Good',
  POOR = 'Poor',
  BAD = 'Bad',
  VERY_BAD = 'VeryBad',
  DOWN = 'Down'
}

export class RealtimeNetworkQuality {
  readonly uplink: RealtimeNetworkQualityLevel;
  readonly downlink: RealtimeNetworkQualityLevel;

  constructor(
    uplink: RealtimeNetworkQualityLevel,
    downlink: RealtimeNetworkQualityLevel
  ) {
    this.uplink = uplink;
    this.downlink = downlink;
  }
}

export type RealtimeNetworkQualityListener = (quality: RealtimeNetworkQuality) => void;
