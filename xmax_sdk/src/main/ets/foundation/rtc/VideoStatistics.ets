//
//  VideoStatistics.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/** Statistics for outgoing RTC video. Unavailable metrics are undefined. */
export class UplinkVideoStatistics {

  /** The actual video width, in pixels. */
  readonly width?: number;

  /** The actual video height, in pixels. */
  readonly height?: number;

  /** The capture frame rate, in fps. */
  readonly captureFrameRate?: number;

  /** The encoding frame rate, in fps. */
  readonly encodeFrameRate?: number;

  /** The transmission frame rate, in fps. */
  readonly sendFrameRate?: number;

  /** The sending bitrate, in kbps. */
  readonly bitrateKbps?: number;

  /** The packet loss to the RTC service, in percent from 0 to 100, retaining fractions. */
  readonly packetLossPercent?: number;

  /** Creates an uplink statistics snapshot. */
  constructor(
    width?: number,
    height?: number,
    captureFrameRate?: number,
    encodeFrameRate?: number,
    sendFrameRate?: number,
    bitrateKbps?: number,
    packetLossPercent?: number
  ) {
    this.width = width;
    this.height = height;
    this.captureFrameRate = captureFrameRate;
    this.encodeFrameRate = encodeFrameRate;
    this.sendFrameRate = sendFrameRate;
    this.bitrateKbps = bitrateKbps;
    this.packetLossPercent = packetLossPercent;
  }
}

/** Statistics for incoming RTC video. Unavailable metrics are undefined. */
export class DownlinkVideoStatistics {

  /** The remote user identifier for the current result stream. */
  readonly userId: string;

  /** The actual video width, in pixels. */
  readonly width?: number;

  /** The actual video height, in pixels. */
  readonly height?: number;

  /** The decoding frame rate, in fps. */
  readonly decodeFrameRate?: number;

  /** The RTC rendering frame rate, excluding client interpolation. */
  readonly renderFrameRate?: number;

  /** The receiving bitrate, in kbps. */
  readonly bitrateKbps?: number;

  /** The packet loss in percent from 0 to 100, retaining fractions. */
  readonly packetLossPercent?: number;

  /** The RTC media end-to-end delay, in milliseconds; not the full AI generation latency. */
  readonly endToEndDelayMs?: number;

  /** Creates a downlink statistics snapshot. */
  constructor(
    userId: string,
    width?: number,
    height?: number,
    decodeFrameRate?: number,
    renderFrameRate?: number,
    bitrateKbps?: number,
    packetLossPercent?: number,
    endToEndDelayMs?: number
  ) {
    this.userId = userId;
    this.width = width;
    this.height = height;
    this.decodeFrameRate = decodeFrameRate;
    this.renderFrameRate = renderFrameRate;
    this.bitrateKbps = bitrateKbps;
    this.packetLossPercent = packetLossPercent;
    this.endToEndDelayMs = endToEndDelayMs;
  }
}

/**
 * Delivers asynchronously on the ArkTS event loop; undefined clears statistics on unpublishing or
 * disconnect.
 *
 * @param statistics The normalized statistics, or undefined to clear prior values.
 */
export type UplinkVideoStatisticsListener = (
  statistics: UplinkVideoStatistics | undefined
) => void;

/**
 * Delivers only the matching result stream's statistics; undefined clears them on stream cleanup or
 * disconnect.
 *
 * @param statistics The normalized statistics, or undefined to clear prior values.
 */
export type DownlinkVideoStatisticsListener = (
  statistics: DownlinkVideoStatistics | undefined
) => void;
