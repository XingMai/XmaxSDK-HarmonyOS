//
//  MediaServicing.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { RealtimeMediaSource } from './RealtimeMediaSource';
import { ImageSize } from './ImageSize';
import { ModelDefinition } from '../realtime/RealtimeModel';

/** The sizing rules for a realtime model's local media, generation canvases, and returned media. */
export interface MediaServicing {

  /** The model definition used for media rules. */
  readonly model: ModelDefinition;

  /**
   * Resolves aligned local dimensions and validates camera resolution buckets.
   *
   * @param size The requested camera dimensions or oriented image or video dimensions, in pixels.
   * @param source The media source; camera dimensions must match a bucket when the model defines
   * fixed resolutions.
   *
   * @returns Dimensions aligned to 4 within the model's maximum pixel area, preserving the exact
   * aspect ratio when possible and rounding down otherwise. External sources are also upscaled
   * to the model's minimum pixel area; other local media is never upscaled.
   *
   * @throws An INVALID_CONFIGURATION error if dimensions or pixel area are invalid, a camera
   * resolution is unsupported, or no aligned size of at least 4 × 4 pixels fits the limit.
   */
  resolveMediaSize(
    size: ImageSize,
    source: RealtimeMediaSource
  ): ImageSize;

  /**
   * Selects a generation canvas by aspect ratio independently of local media dimensions.
   *
   * @param size The processed local media dimensions defining the generation aspect ratio.
   *
   * @returns The canvas matching fixed model dimensions or pixel-area and alignment constraints.
   *
   * @throws An INVALID_CONFIGURATION error if dimensions or their pixel area are not positive
   * safe integers.
   */
  resolveGenerationSize(
    size: ImageSize
  ): ImageSize;

  /**
   * Resolves aspect-preserving return dimensions within width, height, and optional interpolation
   * limits.
   *
   * @param size The processed local media dimensions defining the result's aspect ratio.
   * @param maximumSize The positive, finite maximum result dimensions; fractional pixels are
   * allowed.
   * @param frameInterpolationEnabled Whether to cap the returned area at 900000 pixels; defaults
   * to false. This does not check device interpolation support.
   *
   * @returns Dimensions aligned to 4 within the limits, without upscaling local media. The exact
   * aspect ratio is preserved when possible; otherwise, dimensions are rounded down.
   *
   * @throws An INVALID_CONFIGURATION error if source dimensions or pixel area are invalid, bounds
   * are nonpositive or nonfinite, or the limits cannot fit at least 4 × 4 pixels.
   */
  resolveTargetSize(
    size: ImageSize,
    maximumSize: ImageSize,
    frameInterpolationEnabled?: boolean
  ): ImageSize;
}
