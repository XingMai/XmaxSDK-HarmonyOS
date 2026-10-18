import { RealtimeNetworkQualityLevel } from '../../service/realtime/RealtimeNetworkQuality';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import { EncodingBitratePolicy } from '../encoding/EncodingBitratePolicy';
import { QualityVideoFormat } from './QualityVideoFormat';

/** 单个传输方向的连续采样、稳定窗口及升降档规则。 */
export class QualityDirection {
  readonly baseline: RealtimeVideoFormat;
  private readonly downlink: boolean;
  private currentLevel: number;
  private goodSamples: number = 0;
  private poorSamples: number = 0;
  private lastSample: number | undefined;
  private stableUntil: number = 0;
  private upgradeAfter: number = 0;
  private probeUntil: number = 0;

  constructor(baseline: RealtimeVideoFormat, level: number, downlink: boolean) {
    this.baseline = baseline;
    this.downlink = downlink;
    this.currentLevel = Math.min(5, Math.max(1, Math.round(level)));
    while (this.currentLevel > 1 && !this.supports(this.currentLevel)) { this.currentLevel--; }
  }
  get level(): number { return this.currentLevel; }
  get format(): RealtimeVideoFormat { return this.formatAt(this.currentLevel); }
  private formatAt(level: number): RealtimeVideoFormat {
    return QualityVideoFormat.resolve(this.baseline, level, this.downlink);
  }
  resetSamples(): void {
    this.goodSamples = 0;
    this.poorSamples = 0;
    this.lastSample = undefined;
  }
  observe(quality: RealtimeNetworkQualityLevel, sampledAt: number, now: number): number | undefined {
    if (!Number.isFinite(sampledAt) || !Number.isFinite(now) || sampledAt > now ||
      (this.lastSample !== undefined && sampledAt <= this.lastSample)) { return undefined; }
    if (this.lastSample !== undefined && sampledAt - this.lastSample > 5) { this.resetSamples(); }
    this.lastSample = sampledAt;
    if (now - sampledAt > 5 || now < this.stableUntil) {
      this.goodSamples = 0;
      this.poorSamples = 0;
      return undefined;
    }
    let step: number;
    switch (quality) {
      case RealtimeNetworkQualityLevel.BAD:
      case RealtimeNetworkQualityLevel.VERY_BAD:
        this.goodSamples = 0;
        this.poorSamples++;
        if (this.poorSamples < 3) { return undefined; }
        step = 1;
        break;
      case RealtimeNetworkQualityLevel.EXCELLENT:
      case RealtimeNetworkQualityLevel.GOOD:
        this.poorSamples = 0;
        this.goodSamples++;
        if (this.goodSamples < 5 || now < this.upgradeAfter) { return undefined; }
        step = -1;
        break;
      default:
        this.goodSamples = 0;
        this.poorSamples = 0;
        return undefined;
    }
    let candidate: number = this.currentLevel + step;
    while (candidate >= 1 && candidate <= 5) {
      if (!QualityVideoFormat.same(this.formatAt(candidate), this.format) && this.supports(candidate)) { return candidate; }
      candidate += step;
    }
    return undefined;
  }
  complete(next: number, success: boolean, now: number): void {
    this.resetSamples();
    this.stableUntil = now + 4;
    if (!success) { return; }
    if (next < this.currentLevel) { this.probeUntil = now + 20; }
    else if (next > this.currentLevel) {
      if (now < this.probeUntil) { this.upgradeAfter = now + 60; }
      this.probeUntil = 0;
    }
    this.currentLevel = next;
  }
  private supports(level: number): boolean {
    if (this.downlink) { return true; }
    try { EncodingBitratePolicy.resolve(this.formatAt(level)); return true; }
    catch (_error) { return false; }
  }
}
