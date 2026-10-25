//
//  MediaService.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { RealtimeMediaSource } from './RealtimeMediaSource';
import { ImageSize } from './ImageSize';
import { MediaServicing } from './MediaServicing';
import { ModelDefinition, RealtimeModel, RealtimeModels } from '../realtime/RealtimeModel';
import { XmaxError, XmaxErrorCode } from '../../foundation/errors/XmaxError';

/** The sizing rules for local media, generation canvases, and returned media. */
export class MediaService implements MediaServicing {

  /** The model defining media sizing and generation constraints. */
  readonly model: ModelDefinition;

  /** Creates a media service for a model. */
  constructor(
    model: ModelDefinition = RealtimeModels.realtime(RealtimeModel.X2_0)
  ) {
    this.model = model;
  }

  /** Validates camera buckets and resolves aligned local dimensions, upscaling external input if required. */
  resolveMediaSize(
    size: ImageSize,
    source: RealtimeMediaSource
  ): ImageSize {
    this.validateSize(size);

    const buckets: ImageSize[] = this.model.resolutionBuckets;
    if (source === RealtimeMediaSource.CAMERA && buckets.length > 0 &&
      !buckets.some((bucket: ImageSize): boolean => bucket.width === size.width && bucket.height === size.height)) {
      const supportedSizes: string = buckets.map((bucket: ImageSize): string =>
        `${bucket.width}×${bucket.height}`).join(', ');
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        `Model ${this.model.name} does not support camera resolution ${size.width}×${size.height}. ` +
        `Supported resolutions: ${supportedSizes}`
      );
    }

    const pixels: number = size.width * size.height;
    const scale: number = source === RealtimeMediaSource.EXTERNAL && pixels < this.model.minimumInputPixels ?
      Math.sqrt(this.model.minimumInputPixels / pixels) : Math.min(1, Math.sqrt(this.model.maximumInputPixels / pixels));
    const resolved: ImageSize = this.alignedSize(
      size,
      scale
    );
    if (source === RealtimeMediaSource.EXTERNAL &&
      resolved.width * resolved.height < this.model.minimumInputPixels) {
      const minimumScale: number = Math.sqrt(this.model.minimumInputPixels / pixels);
      const width: number = Math.ceil(size.width * minimumScale / 4) * 4;
      const height: number = Math.ceil(size.height * minimumScale / 4) * 4;
      if (width * height <= this.model.maximumInputPixels) {
        return new ImageSize(width, height);
      }
      return this.boundedAlignedSize(size.width * minimumScale, size.height * minimumScale);
    }
    return resolved;
  }

  /** Selects a generation canvas without changing the local media dimensions. */
  resolveGenerationSize(
    size: ImageSize
  ): ImageSize {
    this.validateSize(size);

    const aspect: number = size.width / size.height;
    const buckets: ImageSize[] = this.model.resolutionBuckets;
    if (buckets.length > 0) {
      let best: ImageSize = buckets[0];
      let distance: number = Math.abs(Math.log(aspect / (best.width / best.height)));

      for (let index: number = 1; index < buckets.length; index++) {
        const candidate: ImageSize = buckets[index];
        const candidateDistance: number = Math.abs(Math.log(aspect / (candidate.width / candidate.height)));
        if (candidateDistance < distance) {
          best = candidate;
          distance = candidateDistance;
        }
      }

      return best;
    }

    const sourceWidth: number = size.width;
    const sourceHeight: number = size.height;
    const pixels: number = sourceWidth * sourceHeight;
    if (!Number.isFinite(pixels) || pixels <= 0) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Image pixel count must be finite and positive'
      );
    }

    let scale: number = 1;
    let rounding: (
      value: number
    ) => number = Math.round;
    if (pixels < this.model.minimumInputPixels) {
      scale = Math.sqrt(this.model.minimumInputPixels / pixels);
      rounding = Math.ceil;
    } else if (pixels > this.model.maximumInputPixels) {
      scale = Math.sqrt(this.model.maximumInputPixels / pixels);
      rounding = Math.floor;
    }

    const alignment: number = this.model.inputSizeAlignment;
    const width: number = Math.max(
      rounding(sourceWidth * scale / alignment) * alignment,
      alignment
    );
    const height: number = Math.max(
      rounding(sourceHeight * scale / alignment) * alignment,
      alignment
    );

    const alignedPixels: number = width * height;
    if (alignedPixels >= this.model.minimumInputPixels && alignedPixels <= this.model.maximumInputPixels) {
      return new ImageSize(
        width,
        height
      );
    }

    return this.boundedAlignedSize(
      sourceWidth * scale,
      sourceHeight * scale
    );
  }

  /** Resolves aligned return dimensions within size and optional interpolation limits. */
  resolveTargetSize(
    size: ImageSize,
    maximumSize: ImageSize,
    frameInterpolationEnabled: boolean = false
  ): ImageSize {
    this.validateSize(size);
    if (!Number.isFinite(maximumSize.width) || !Number.isFinite(maximumSize.height) ||
      maximumSize.width <= 0 || maximumSize.height <= 0) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Target bounds must be positive and finite'
      );
    }

    let scale: number = Math.min(1, maximumSize.width / size.width, maximumSize.height / size.height);
    const pixels: number = size.width * scale * size.height * scale;
    if (frameInterpolationEnabled && pixels > 900000) {
      scale *= Math.sqrt(900000 / pixels);
    }

    return this.alignedSize(
      size,
      scale
    );
  }

  /**
   * Validates positive safe-integer dimensions and pixel area, throwing a configuration error if
   * invalid.
   *
   * @param size The media dimensions to validate, in pixels.
   */
  private validateSize(
    size: ImageSize
  ): void {
    if (!Number.isSafeInteger(size.width) || !Number.isSafeInteger(size.height) ||
      size.width <= 0 || size.height <= 0 || !Number.isSafeInteger(size.width * size.height)) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Media dimensions must be positive integers'
      );
    }
  }

  /**
   * Prefers integer multiples of the reduced aspect ratio; otherwise aligns dimensions downward
   * independently.
   *
   * @param size The original media dimensions, in pixels.
   * @param scale The scale applied to width and height.
   *
   * @returns The resolved media dimensions.
   */
  private alignedSize(
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

    const alignedScale: number = Math.floor(divisor * scale / 4) * 4;
    if (alignedScale >= 4) {
      return new ImageSize(
        size.width / divisor * alignedScale,
        size.height / divisor * alignedScale
      );
    }

    const width: number = Math.floor(size.width * scale / 4) * 4;
    const height: number = Math.floor(size.height * scale / 4) * 4;
    if (width < 4 || height < 4) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'No aligned video size is available within the size limits'
      );
    }

    return new ImageSize(
      width,
      height
    );
  }

  /**
   * Selects a valid-area canvas nearest the target when alignment exceeds area bounds.
   *
   * @param width The frame width, in pixels.
   * @param height The frame height, in pixels.
   *
   * @returns The resolved media dimensions.
   */
  private boundedAlignedSize(
    width: number,
    height: number
  ): ImageSize {
    const alignment: number = this.model.inputSizeAlignment;
    const unitPixels: number = alignment * alignment;
    const minimumUnits: number = Math.ceil(this.model.minimumInputPixels / unitPixels);
    const maximumUnits: number = Math.floor(this.model.maximumInputPixels / unitPixels);

    let bestWidth: number = alignment;
    let bestHeight: number = minimumUnits * alignment;
    let bestDistance: number = Infinity;

    for (let widthUnits: number = 1; widthUnits <= maximumUnits; widthUnits++) {
      const minimumHeight: number = Math.ceil(minimumUnits / widthUnits);
      const maximumHeight: number = Math.floor(maximumUnits / widthUnits);
      if (minimumHeight > maximumHeight) {
        continue;
      }

      const heightUnits: number = Math.min(Math.max(Math.round(height / alignment), minimumHeight), maximumHeight);
      const candidateWidth: number = widthUnits * alignment;
      const candidateHeight: number = heightUnits * alignment;
      const distance: number = Math.pow(
        (candidateWidth - width) / width,
        2
      ) +
        Math.pow(
          (candidateHeight - height) / height,
          2
        );

      if (distance < bestDistance) {
        bestDistance = distance;
        bestWidth = candidateWidth;
        bestHeight = candidateHeight;
      }
    }

    return new ImageSize(
      bestWidth,
      bestHeight
    );
  }
}
