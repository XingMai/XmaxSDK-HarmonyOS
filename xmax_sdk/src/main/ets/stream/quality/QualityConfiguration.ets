//
//  QualityConfiguration.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import { RealtimeNetworkQuality } from '../../service/realtime/RealtimeNetworkQuality';
import { QualityVideoFormat } from './QualityVideoFormat';

/**
 * Receives network quality with monotonic sample time for adaptive generation scheduling.
 *
 * @param quality The uplink, downlink, or combined network quality sample.
 * @param sampledAt The monotonic network sample time, in seconds.
 */
export type AdaptiveQualityListener = (
  quality: RealtimeNetworkQuality,
  sampledAt: number
) => void;

/** The fixed media baseline and quality levels defining uplink/downlink formats. */
export class QualityConfiguration {

  /** The fixed media format preserving aspect ratio and encoder settings. */
  readonly baseline: RealtimeVideoFormat;

  /** The uplink quality level, from 1 to 5 with lower values indicating higher quality. */
  readonly uplinkLevel: number;

  /** The downlink quality level, from 1 to 5 with lower values indicating higher quality. */
  readonly downlinkLevel: number;

  /** The minimum uplink pixel area; downlink is not constrained by this value. */
  readonly minimumInputPixels: number;

  /** Creates a transmission quality configuration. */
  constructor(
    baseline: RealtimeVideoFormat,
    uplinkLevel: number,
    downlinkLevel: number,
    minimumInputPixels: number = 0
  ) {
    this.baseline = baseline;
    this.uplinkLevel = uplinkLevel;
    this.downlinkLevel = downlinkLevel;
    this.minimumInputPixels = minimumInputPixels;
  }

  /** The current uplink format, preserving explicit bitrate and encoder preferences. */
  get uplink(): RealtimeVideoFormat {
    return QualityVideoFormat.resolve(
      this.baseline,
      this.uplinkLevel,
      false,
      this.minimumInputPixels
    );
  }

  /** The current downlink format defining result dimensions and bitrate budget. */
  get downlink(): RealtimeVideoFormat {
    return QualityVideoFormat.resolve(
      this.baseline,
      this.downlinkLevel,
      true
    );
  }
}

/** Recommended uplink/downlink levels; absent directions retain their current level. */
export class QualityChange {

  /** The uplink quality level or recommendation. */
  readonly uplink?: number;

  /** The downlink quality level or recommendation. */
  readonly downlink?: number;

  /** Creates a quality change recommendation. */
  constructor(
    uplink?: number,
    downlink?: number
  ) {
    this.uplink = uplink;
    this.downlink = downlink;
  }
}
