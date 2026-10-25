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
  private static readonly scales: number[] = [1, 0.9, 0.75, 0.6, 0.5];

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
   * @param minimumInputPixels The minimum uplink pixel area; defaults to zero and is ignored for
   * downlink.
   *
   * @returns The transmission format for the direction and level.
   */
  static resolve(
    baseline: RealtimeVideoFormat,
    level: number,
    downlink: boolean,
    minimumInputPixels: number = 0
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
      scale,
      downlink ? 2 : 4,
      downlink ? 0 : minimumInputPixels
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
   * Downscales within alignment and minimum-area limits, preserving exact aspect ratio when
   * possible.
   *
   * @param size The unscaled local media dimensions, in pixels.
   * @param scale The scale applied to width and height.
   * @param alignment The required multiple for output dimensions.
   * @param minimumPixels The minimum output area, capped at the source area to prevent upscaling.
   *
   * @returns Aligned dimensions satisfying the minimum area without upscaling.
   */
  private static scaledSize(
    size: ImageSize,
    scale: number,
    alignment: number,
    minimumPixels: number
  ): ImageSize {
    let divisor: number = size.width;
    let remainder: number = size.height;
    while (remainder !== 0) {
      const next: number = divisor % remainder;
      divisor = remainder;
      remainder = next;
    }
    const pixels: number = size.width * size.height;
    const minimumScale: number = Math.sqrt(Math.min(Math.max(0, minimumPixels), pixels) / pixels);
    const minimumUnits: number = Math.ceil(divisor * minimumScale / alignment) * alignment;
    const units: number = Math.floor(Math.floor(divisor * scale + 0.0000001) / alignment) * alignment;
    const resolvedUnits: number = Math.max(units, minimumUnits);
    if (units >= alignment && resolvedUnits <= divisor) {
      return new ImageSize(
        size.width / divisor * resolvedUnits,
        size.height / divisor * resolvedUnits
      );
    }
    return new ImageSize(
      Math.max(alignment, Math.max(
        Math.floor(size.width * scale / alignment) * alignment,
        Math.ceil(size.width * minimumScale / alignment) * alignment
      )),
      Math.max(alignment, Math.max(
        Math.floor(size.height * scale / alignment) * alignment,
        Math.ceil(size.height * minimumScale / alignment) * alignment
      ))
    );
  }
}
