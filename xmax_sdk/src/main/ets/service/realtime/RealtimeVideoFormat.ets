//
//  RealtimeVideoFormat.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import {
  XmaxError,
  XmaxErrorCode
} from '../../foundation/errors/XmaxError';

/** An uplink encoder preference favoring balance, frame rate, or resolution. */
export enum RealtimeVideoEncoderPreference {

  /** Balances frame rate and resolution. */
  AUTO = 'Auto',

  /** Prioritizes frame rate. */
  MAINTAIN_FRAMERATE = 'MaintainFramerate',

  /** Prioritizes image clarity. */
  MAINTAIN_QUALITY = 'MaintainQuality'
}

/** Realtime video dimensions, frame rate, and uplink encoding settings. */
export class RealtimeVideoFormat {

  /** The positive even video width, in pixels. */
  readonly width: number;

  /** The positive even video height, in pixels. */
  readonly height: number;

  /** The positive integer video frame rate, in fps. */
  readonly fps: number;

  /** The minimum uplink bitrate, in kbps; undefined uses 100, zero removes the minimum. */
  readonly minimumBitrate?: number;

  /**
   * The maximum uplink bitrate, in kbps; undefined uses 0.6 times the final format's reference
   * maximum, at least 100. Explicit values must be positive.
   */
  readonly maximumBitrate?: number;

  /** The uplink encoding preference; defaults to AUTO, balancing frame rate and resolution. */
  readonly encoderPreference: RealtimeVideoEncoderPreference;

  /** Creates a realtime video format. */
  constructor(
    width: number,
    height: number,
    fps: number,
    minimumBitrate?: number,
    maximumBitrate?: number,
    encoderPreference: RealtimeVideoEncoderPreference = RealtimeVideoEncoderPreference.AUTO
  ) {
    this.width = width;
    this.height = height;
    this.fps = fps;
    this.minimumBitrate = minimumBitrate;
    this.maximumBitrate = maximumBitrate;
    this.encoderPreference = encoderPreference;
  }

  /**
   * Validates dimensions, frame rate, bitrate, and preference, throwing a configuration error if
   * invalid.
   */
  validate(): void {
    if (!Number.isSafeInteger(this.width) || !Number.isSafeInteger(this.height) ||
      !Number.isSafeInteger(this.fps) || this.width <= 0 || this.height <= 0 || this.fps <= 0 ||
      this.width % 2 !== 0 || this.height % 2 !== 0) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Realtime video width and height must be positive even numbers, and fps must be greater than zero'
      );
    }

    if (this.minimumBitrate !== undefined &&
      (!Number.isSafeInteger(this.minimumBitrate) || this.minimumBitrate < 0)) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Minimum bitrate must be a non-negative integer'
      );
    }
    if (this.maximumBitrate !== undefined &&
      (!Number.isSafeInteger(this.maximumBitrate) || this.maximumBitrate <= 0)) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Maximum bitrate must be a positive integer'
      );
    }
    if (this.minimumBitrate !== undefined && this.maximumBitrate !== undefined &&
      this.minimumBitrate > this.maximumBitrate) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Minimum bitrate must not exceed maximum bitrate'
      );
    }

    switch (this.encoderPreference) {
      case RealtimeVideoEncoderPreference.AUTO:
      case RealtimeVideoEncoderPreference.MAINTAIN_FRAMERATE:
      case RealtimeVideoEncoderPreference.MAINTAIN_QUALITY:
        break;
      default:
        throw new XmaxError(
          XmaxErrorCode.INVALID_CONFIGURATION,
          'Unsupported video encoder preference'
        );
    }
  }

  /**
   * Returns resized dimensions while preserving frame rate and encoding settings.
   *
   * @param width The frame width, in pixels.
   * @param height The frame height, in pixels.
   *
   * @returns The resolved or updated video format.
   */
  resized(
    width: number,
    height: number
  ): RealtimeVideoFormat {
    return new RealtimeVideoFormat(
      width,
      height,
      this.fps,
      this.minimumBitrate,
      this.maximumBitrate,
      this.encoderPreference
    );
  }
}
