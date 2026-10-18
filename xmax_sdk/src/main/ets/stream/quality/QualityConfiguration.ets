import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import { RealtimeNetworkQuality } from '../../service/realtime/RealtimeNetworkQuality';
import { QualityVideoFormat } from './QualityVideoFormat';

export type AdaptiveQualityListener = (quality: RealtimeNetworkQuality, sampledAt: number) => void;

export class QualityConfiguration {
  readonly baseline: RealtimeVideoFormat;
  readonly uplinkLevel: number;
  readonly downlinkLevel: number;
  constructor(baseline: RealtimeVideoFormat, uplinkLevel: number, downlinkLevel: number) {
    this.baseline = baseline;
    this.uplinkLevel = uplinkLevel;
    this.downlinkLevel = downlinkLevel;
  }
  get uplink(): RealtimeVideoFormat { return QualityVideoFormat.resolve(this.baseline, this.uplinkLevel, false); }
  get downlink(): RealtimeVideoFormat { return QualityVideoFormat.resolve(this.baseline, this.downlinkLevel, true); }
}

export class QualityChange {
  readonly uplink?: number;
  readonly downlink?: number;
  constructor(uplink?: number, downlink?: number) {
    this.uplink = uplink;
    this.downlink = downlink;
  }
}
