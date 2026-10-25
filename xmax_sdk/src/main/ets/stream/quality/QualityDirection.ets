//
//  QualityDirection.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { RealtimeNetworkQualityLevel } from '../../service/realtime/RealtimeNetworkQuality';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import { EncodingBitratePolicy } from '../encoding/EncodingBitratePolicy';
import { QualityVideoFormat } from './QualityVideoFormat';

/** Per-direction sampling, stability windows, and quality adjustment policy. */
export class QualityDirection {

  /** The fixed media format preserving aspect ratio and encoder settings. */
  readonly baseline: RealtimeVideoFormat;

  /** The minimum uplink pixel area; ignored for downlink. */
  readonly minimumInputPixels: number;

  /** The downlink quality level or recommendation. */
  private readonly downlink: boolean;

  /** The successfully applied transmission quality level. */
  private currentLevel: number;

  /** The consecutive good-quality sample count. */
  private goodSamples: number = 0;

  /** The consecutive poor-quality sample count. */
  private poorSamples: number = 0;

  /** The previous monotonic sample time, in seconds. */
  private lastSample: number | undefined;

  /** The monotonic end of the quality stability window, in seconds. */
  private stableUntil: number = 0;

  /** The earliest monotonic time for a quality upgrade, in seconds. */
  private upgradeAfter: number = 0;

  /** The monotonic end of the upgrade probing window, in seconds. */
  private probeUntil: number = 0;

  /**
   * Creates per-direction adaptive quality state.
   *
   * @param baseline The baseline preserving media aspect ratio and explicit encoding settings.
   * @param level The quality level, from 1 to 5; lower values mean higher quality.
   * @param downlink Whether this is downlink; false selects uplink.
   * @param minimumInputPixels The minimum uplink pixel area; defaults to zero.
   */
  constructor(
    baseline: RealtimeVideoFormat,
    level: number,
    downlink: boolean,
    minimumInputPixels: number = 0
  ) {
    this.baseline = baseline;
    this.downlink = downlink;
    this.minimumInputPixels = minimumInputPixels;

    this.currentLevel = Math.min(5, Math.max(1, Math.round(level)));
    while (this.currentLevel > 1 && !this.supports(this.currentLevel)) { this.currentLevel--; }
  }

  /** The successfully submitted quality level from 1 to 5; lower values mean higher quality. */
  get level(): number {
    return this.currentLevel;
  }

  /** The applied quality level's transmission format for this direction. */
  get format(): RealtimeVideoFormat {
    return this.formatAt(this.currentLevel);
  }

  /**
   * Resolves a level's format for this direction.
   *
   * @param level The quality level, from 1 to 5; lower values mean higher quality.
   *
   * @returns The level's transmission format.
   */
  private formatAt(
    level: number
  ): RealtimeVideoFormat {
    return QualityVideoFormat.resolve(
      this.baseline,
      level,
      this.downlink,
      this.minimumInputPixels
    );
  }

  /** Clears consecutive good/bad samples and the last sample time. */
  resetSamples(): void {
    this.goodSamples = 0;
    this.poorSamples = 0;
    this.lastSample = undefined;
  }

  /**
   * Accumulates valid samples and recommends a level after count and stability thresholds.
   *
   * @param quality The uplink, downlink, or combined network quality sample.
   * @param sampledAt The monotonic network sample time, in seconds.
   * @param now The current monotonic time, in seconds.
   *
   * @returns The recommended level, or undefined for invalid samples, active stability windows, or
   * no required change.
   */
  observe(
    quality: RealtimeNetworkQualityLevel,
    sampledAt: number,
    now: number
  ): number | undefined {
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
      if (!QualityVideoFormat.same(
        this.formatAt(candidate),
        this.format
      ) && this.supports(candidate)) { return candidate; }
      candidate += step;
    }
    return undefined;
  }

  /**
   * Records submission and probing windows, changing current level only on success.
   *
   * @param next The requested transmission quality level.
   * @param success Whether the configuration was submitted successfully.
   * @param now The current monotonic time, in seconds.
   */
  complete(
    next: number,
    success: boolean,
    now: number
  ): void {
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

  /**
   * Checks whether a level's format and bitrate are supported for this direction.
   *
   * @param level The quality level, from 1 to 5; lower values mean higher quality.
   *
   * @returns True if the level configuration can be submitted.
   */
  private supports(
    level: number
  ): boolean {
    if (this.downlink) { return true; }
    try { EncodingBitratePolicy.resolve(this.formatAt(level)); return true; }
    catch (_error) { return false; }
  }
}
