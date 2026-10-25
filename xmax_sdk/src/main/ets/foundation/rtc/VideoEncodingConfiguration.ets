//
//  VideoEncodingConfiguration.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/** An encoder preference favoring smoothness, clarity, or balance. */
export enum VideoEncoderPreference {

  /** Balances frame rate and resolution. */
  AUTO,

  /** Prioritizes frame rate. */
  MAINTAIN_FRAMERATE,

  /** Prioritizes image clarity. */
  MAINTAIN_QUALITY
}

/** Uplink encoding dimensions, frame rate, bitrate bounds, and preference. */
export class VideoEncodingConfiguration {

  /** The encoded width, in pixels. */
  readonly width: number;

  /** The encoded height, in pixels. */
  readonly height: number;

  /** The video frame rate, in fps. */
  readonly frameRate: number;

  /** The minimum video bitrate, in kbps. */
  readonly minimumBitrate: number;

  /** The optional maximum video bitrate, in kbps. */
  readonly maximumBitrate: number;

  /** The balance between video clarity and smoothness. */
  readonly encoderPreference: VideoEncoderPreference;

  /** Creates a video encoding configuration. */
  constructor(
    width: number,
    height: number,
    frameRate: number,
    minimumBitrate: number = 0,
    maximumBitrate: number = -1,
    encoderPreference: VideoEncoderPreference = VideoEncoderPreference.AUTO
  ) {
    this.width = width;
    this.height = height;
    this.frameRate = frameRate;
    this.minimumBitrate = minimumBitrate;
    this.maximumBitrate = maximumBitrate;
    this.encoderPreference = encoderPreference;
  }
}
