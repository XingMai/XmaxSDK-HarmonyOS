//
//  RealtimeNetworkQuality.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/** A network quality level for uplink or downlink. */
export enum RealtimeNetworkQualityLevel {

  /** Network quality is unavailable. */
  UNKNOWN = 'Unknown',

  /** Excellent network quality. */
  EXCELLENT = 'Excellent',

  /** Good network quality. */
  GOOD = 'Good',

  /** Poor network quality. */
  POOR = 'Poor',

  /** Bad network quality. */
  BAD = 'Bad',

  /** Very bad network quality. */
  VERY_BAD = 'VeryBad',

  /** The network is disconnected. */
  DOWN = 'Down'
}

/** The local uplink and downlink network quality. */
export class RealtimeNetworkQuality {

  /** The uplink quality level or recommendation. */
  readonly uplink: RealtimeNetworkQualityLevel;

  /** The downlink quality level or recommendation. */
  readonly downlink: RealtimeNetworkQualityLevel;

  /** Creates a network quality snapshot. */
  constructor(
    uplink: RealtimeNetworkQualityLevel,
    downlink: RealtimeNetworkQualityLevel
  ) {
    this.uplink = uplink;
    this.downlink = downlink;
  }
}

/**
 * Receives uplink and downlink network quality changes.
 *
 * @param quality The uplink, downlink, or combined network quality sample.
 */
export type RealtimeNetworkQualityListener = (
  quality: RealtimeNetworkQuality
) => void;
