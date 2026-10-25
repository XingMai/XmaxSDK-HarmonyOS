//
//  QualityVideoFormat.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { ImageSize } from '../../service/media/ImageSize';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';

/**
 * Changes transmission format only, preserving capture, generation canvas, and interaction
 * coordinates.
 */
export class QualityVideoFormat {

  /** The dimension scaling factors for each quality level. */
  private static readonly scales: number[] = [1, 0.8, 0.65, 0.5, 0.5];

  /** The frame-rate limits for each quality level. */
  private static readonly frameRates: number[] = [30, 24, 24, 20, 16];

  /**
   * Compares dimensions, rate, bitrate bounds, and preference of two formats.
   *
   * @param first The first video format.
   * @param second The second video format.
   *
   * @returns True if all encoding settings match.
   */
  static same(
    first: RealtimeVideoFormat,
    second: RealtimeVideoFormat
  ): boolean {
    return first.width === second.width && first.height === second.height && first.fps === second.fps &&
      first.minimumBitrate === second.minimumBitrate && first.maximumBitrate === second.maximumBitrate &&
      first.encoderPreference === second.encoderPreference;
  }

  /**
   * Resolves downlink dimension limits while preserving the short side and avoiding upscaling.
   *
   * @param baseline The baseline preserving media aspect ratio and explicit encoding settings.
   * @param level The quality level, from 1 to 5; lower values mean higher quality.
   *
   * @returns The dimension limits for result target sizing.
   */
  static resolveDownlinkMaximumSize(
    baseline: RealtimeVideoFormat,
    level: number
  ): ImageSize {
    baseline.validate();
    const scale: number = QualityVideoFormat.sizeScale(
      baseline,
      level
    );
    return new ImageSize(
      baseline.width * scale,
      baseline.height * scale
    );
  }

  /**
   * Resolves level dimensions and rate, preserving explicit uplink encoder settings.
   *
   * @param baseline The baseline preserving media aspect ratio and explicit encoding settings.
   * @param level The quality level, from 1 to 5; lower values mean higher quality.
   * @param downlink Whether this is downlink; false selects uplink.
   *
   * @returns The transmission format for the direction and level.
   */
  static resolve(
    baseline: RealtimeVideoFormat,
    level: number,
    downlink: boolean
  ): RealtimeVideoFormat {
    baseline.validate();
    const index: number = QualityVideoFormat.index(level);
    const scale: number = QualityVideoFormat.sizeScale(
      baseline,
      level
    );
    const size: ImageSize = QualityVideoFormat.scaledSize(
      new ImageSize(
        baseline.width,
        baseline.height
      ),
      scale
    );
    return new RealtimeVideoFormat(
      size.width,
      size.height,
      downlink ? 24 : Math.min(baseline.fps, QualityVideoFormat.frameRates[index]),
      downlink ? undefined : baseline.minimumBitrate,
      downlink ? undefined : baseline.maximumBitrate,
      baseline.encoderPreference
    );
  }

  /**
   * Clamps a level to 1 through 5 and returns its array index.
   *
   * @param level The quality level, from 1 to 5; lower values mean higher quality.
   *
   * @returns The level index in 0 to 4.
   */
  private static index(
    level: number
  ): number {
    return Math.min(5, Math.max(1, Math.round(level))) - 1;
  }

  /**
   * Resolves scaling while keeping the short side at least the smaller of its original size and 240
   * pixels.
   *
   * @param baseline The baseline preserving media aspect ratio and explicit encoding settings.
   * @param level The quality level, from 1 to 5; lower values mean higher quality.
   *
   * @returns The dimension scale, not exceeding one.
   */
  private static sizeScale(
    baseline: RealtimeVideoFormat,
    level: number
  ): number {
    const shortSide: number = Math.min(baseline.width, baseline.height);
    return Math.max(QualityVideoFormat.scales[QualityVideoFormat.index(level)], Math.min(shortSide, 240) / shortSide);
  }

  /**
   * Downscales to even dimensions, preserving exact aspect ratio where possible.
   *
   * @param size The unscaled local media dimensions, in pixels.
   * @param scale The scale applied to width and height.
   *
   * @returns The even dimensions suitable for video encoding.
   */
  private static scaledSize(
    size: ImageSize,
    scale: number
  ): ImageSize {
    let divisor: number = size.width;
    let remainder: number = size.height;
    while (remainder !== 0) {
      const next: number = divisor % remainder;
      divisor = remainder;
      remainder = next;
    }
    const units: number = Math.floor(Math.floor(divisor * scale + 0.0000001) / 2) * 2;
    if (units >= 2) {
      return new ImageSize(
        size.width / divisor * units,
        size.height / divisor * units
      );
    }
    return new ImageSize(
      Math.max(2, Math.floor(size.width * scale / 2) * 2),
      Math.max(2, Math.floor(size.height * scale / 2) * 2)
    );
  }
}
