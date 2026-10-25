//
//  EncodingBitratePolicy.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { XmaxError, XmaxErrorCode } from '../../foundation/errors/XmaxError';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';

/** A reference bitrate at a pixel count or frame rate for interpolation. */
class BitratePoint {

  /** The numeric input represented by this reference point. */
  readonly value: number;

  /** The reference video bitrate, in kbps. */
  readonly bitrate: number;

  /** Creates a bitrate reference point. */
  constructor(
    value: number,
    bitrate: number
  ) {
    this.value = value;
    this.bitrate = bitrate;
  }
}

/** A bitrate budget shared by uplink and downlink, in kbps. */
export class VideoBitrateBudget {

  /** The minimum video bitrate, in kbps. */
  readonly minimum: number;

  /** The maximum video bitrate, in kbps. */
  readonly maximum: number;

  /** Creates a video bitrate budget. */
  constructor(
    minimum: number,
    maximum: number
  ) {
    this.minimum = minimum;
    this.maximum = maximum;
  }
}

/**
 * Resolves bitrate from dimensions and frame rate. The default minimum is 100 kbps; the maximum is
 * 0.6 times the clarity reference, at least 100 kbps.
 */
export class EncodingBitratePolicy {

  /**
   * Validates video format and resolves bitrate bounds, preferring explicit settings.
   *
   * @param format The video format to use.
   *
   * @returns The minimum and maximum bitrates, in kbps.
   */
  static resolve(
    format: RealtimeVideoFormat
  ): VideoBitrateBudget {
    format.validate();
    let maximum: number;
    if (format.maximumBitrate !== undefined) {
      maximum = format.maximumBitrate;
    } else {
      const reference: number = EncodingBitratePolicy.resolveBitrates(
        format.width * format.height,
        format.fps
      )[1] * 0.6;
      const floor: number = Math.floor(reference);
      const rounded: number = reference - floor === 0.5 ? floor + floor % 2 : Math.round(reference);
      maximum = Math.max(100, rounded);
      if (!Number.isSafeInteger(maximum)) {
        throw new XmaxError(
          XmaxErrorCode.INVALID_CONFIGURATION,
          'Realtime video format exceeds the supported bitrate range'
        );
      }
    }
    const minimum: number = format.minimumBitrate ?? 100;
    if (minimum > maximum) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Minimum bitrate must not exceed maximum bitrate after applying SDK defaults'
      );
    }
    return new VideoBitrateBudget(
      minimum,
      maximum
    );
  }

  /** The reference bitrates for video at 15 fps. */
  private static readonly REFERENCE_15_FPS: BitratePoint[] = [
    new BitratePoint(
      120 * 120,
      50
    ),
    new BitratePoint(
      160 * 120,
      65
    ),
    new BitratePoint(
      180 * 180,
      100
    ),
    new BitratePoint(
      240 * 180,
      120
    ),
    new BitratePoint(
      320 * 180,
      140
    ),
    new BitratePoint(
      320 * 240,
      200
    ),
    new BitratePoint(
      424 * 240,
      220
    ),
    new BitratePoint(
      360 * 360,
      260
    ),
    new BitratePoint(
      480 * 360,
      320
    ),
    new BitratePoint(
      640 * 360,
      400
    ),
    new BitratePoint(
      640 * 480,
      500
    ),
    new BitratePoint(
      848 * 480,
      610
    ),
    new BitratePoint(
      960 * 720,
      910
    ),
    new BitratePoint(
      1280 * 720,
      1130
    ),
    new BitratePoint(
      1920 * 1080,
      2080
    )
  ];

  /** The reference bitrates for video at 30 fps. */
  private static readonly REFERENCE_30_FPS: BitratePoint[] = [
    new BitratePoint(
      360 * 360,
      400
    ),
    new BitratePoint(
      480 * 360,
      490
    ),
    new BitratePoint(
      640 * 360,
      600
    ),
    new BitratePoint(
      640 * 480,
      750
    ),
    new BitratePoint(
      848 * 480,
      930
    ),
    new BitratePoint(
      960 * 720,
      1380
    ),
    new BitratePoint(
      1280 * 720,
      1710
    ),
    new BitratePoint(
      1920 * 1080,
      3150
    )
  ];

  /**
   * Interpolates balanced and clarity bitrate references by pixel count and frame rate.
   *
   * @param pixels The total frame pixel count.
   * @param fps The video frame rate, in fps.
   *
   * @returns The balanced and clarity reference bitrates, in kbps.
   */
  private static resolveBitrates(
    pixels: number,
    fps: number
  ): number[] {
    const bitrate15: number = EncodingBitratePolicy.interpolate(
      pixels,
      EncodingBitratePolicy.REFERENCE_15_FPS
    );
    const first30: BitratePoint = EncodingBitratePolicy.REFERENCE_30_FPS[0];
    const bitrate30: number = pixels < first30.value ?
      bitrate15 * (first30.bitrate / EncodingBitratePolicy.interpolate(
        first30.value,
        EncodingBitratePolicy.REFERENCE_15_FPS
      )) :
      EncodingBitratePolicy.interpolate(
        pixels,
        EncodingBitratePolicy.REFERENCE_30_FPS
      );
    const bitrate10: number = bitrate15 * (400 / 500);
    return [
      EncodingBitratePolicy.interpolate(
        fps,
        [
          new BitratePoint(
            10,
            bitrate10
          ), new BitratePoint(
            15,
            bitrate15
          ),
          new BitratePoint(
            30,
            bitrate30
          ), new BitratePoint(
            60,
            bitrate30 * (4780 / 3150)
          )
        ]
      ),
      EncodingBitratePolicy.interpolate(
        fps,
        [
          new BitratePoint(
            10,
            bitrate10 * 2
          ), new BitratePoint(
            15,
            bitrate15 * 2
          ),
          new BitratePoint(
            30,
            bitrate30 * 2
          ), new BitratePoint(
            60,
            bitrate30 * (6500 / 3150)
          )
        ]
      )
    ];
  }

  /**
   * Interpolates reference points linearly and scales out-of-range values from endpoints.
   *
   * @param value The pixel count or frame rate to resolve against the reference points.
   * @param points The touch points to submit or draw.
   *
   * @returns The reference bitrate for the input.
   */
  private static interpolate(
    value: number,
    points: BitratePoint[]
  ): number {
    const first: BitratePoint = points[0];
    if (value <= first.value) {
      return first.bitrate * (value / first.value);
    }
    for (let index: number = 1; index < points.length; index++) {
      const upper: BitratePoint = points[index];
      if (value <= upper.value) {
        const lower: BitratePoint = points[index - 1];
        const ratio: number = (value - lower.value) / (upper.value - lower.value);
        return lower.bitrate + (upper.bitrate - lower.bitrate) * ratio;
      }
    }
    const last: BitratePoint = points[points.length - 1];
    return last.bitrate * (value / last.value);
  }
}
