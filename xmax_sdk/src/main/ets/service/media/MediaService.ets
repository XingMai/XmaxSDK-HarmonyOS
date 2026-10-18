//
//  MediaService.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { RealtimeMediaSource } from '../realtime/RealtimeMediaSource';
import { ImageSize } from './ImageSize';
import { MediaServicing } from './MediaServicing';
import { ModelDefinition, RealtimeModel, RealtimeModels } from '../../core/realtime/RealtimeModel';
import { XmaxError, XmaxErrorCode } from '../../foundation/errors/XmaxError';

/** 提供与模型输入约束相关的媒体业务规则。 */
export class MediaService implements MediaServicing {

  /** 模型媒体约束 */
  readonly model: ModelDefinition;

  /**
   * 创建实时生成业务配置。
   *
   * @param model 实时生成业务使用的模型定义。
   * @returns 新建的 MediaService 实例。
   */
  constructor(model: ModelDefinition = RealtimeModels.realtime(RealtimeModel.X2_0)) {
    this.model = model;
  }

  /**
   * 计算本地媒体帧尺寸：不放大、限制像素面积、优先精确等比并按 4 对齐。
   *
   * @param size 需要计算或发送的画面尺寸。
   * @param source 媒体输入类型，用于选择尺寸处理规则。
   * @returns 计算得到的媒体宽高。
   */
  resolveMediaSize(size: ImageSize, source: RealtimeMediaSource): ImageSize {
    this.validateSize(size);
    const buckets: ImageSize[] = this.model.resolutionBuckets;
    if (source === RealtimeMediaSource.CAMERA && buckets.length > 0 &&
      !buckets.some((bucket: ImageSize): boolean => bucket.width === size.width && bucket.height === size.height)) {
      const supportedSizes: string = buckets.map((bucket: ImageSize): string =>
        `${bucket.width}×${bucket.height}`).join(', ');
      throw new XmaxError(XmaxErrorCode.INVALID_CONFIGURATION,
        `Model ${this.model.name} does not support camera resolution ${size.width}×${size.height}. ` +
        `Supported resolutions: ${supportedSizes}`);
    }
    const scale: number = Math.min(1, Math.sqrt(this.model.maximumInputPixels / (size.width * size.height)));
    return this.alignedSize(size, scale);
  }

  /**
   * 选择模型生成画布，不改变本地媒体规格。
   *
   * @param size 需要计算或发送的画面尺寸。
   * @returns 计算得到的媒体宽高。
   */
  resolveGenerationSize(size: ImageSize): ImageSize {
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
    return this.resolveModelInputSize(size);
  }

  /**
   * 根据回传宽高上限及可选的 90 万像素插帧限制计算尺寸，不改变本地媒体。
   *
   * @param size 需要计算或发送的画面尺寸。
   * @param maximumSize 允许的结果流宽高上限。
   * @param frameInterpolationEnabled 是否将插帧能力纳入目标尺寸约束。
   * @returns 计算得到的媒体宽高。
   */
  resolveTargetSize(size: ImageSize, maximumSize: ImageSize, frameInterpolationEnabled: boolean = false): ImageSize {
    this.validateSize(size);
    if (!Number.isFinite(maximumSize.width) || !Number.isFinite(maximumSize.height) ||
      maximumSize.width <= 0 || maximumSize.height <= 0) {
      throw new XmaxError(XmaxErrorCode.INVALID_CONFIGURATION, 'Target bounds must be positive and finite');
    }
    let scale: number = Math.min(1, maximumSize.width / size.width, maximumSize.height / size.height);
    const pixels: number = size.width * scale * size.height * scale;
    if (frameInterpolationEnabled && pixels > 900000) {
      scale *= Math.sqrt(900000 / pixels);
    }
    return this.alignedSize(size, scale);
  }

  /**
   * 验证媒体宽高为安全正整数且总像素数可安全表示；非法时抛出配置错误。
   *
   * @param size 需要计算或发送的画面尺寸。
   * @returns 无返回值。
   */
  private validateSize(size: ImageSize): void {
    if (!Number.isSafeInteger(size.width) || !Number.isSafeInteger(size.height) ||
      size.width <= 0 || size.height <= 0 || !Number.isSafeInteger(size.width * size.height)) {
      throw new XmaxError(XmaxErrorCode.INVALID_CONFIGURATION, 'Media dimensions must be positive integers');
    }
  }

  /**
   * 使用最简宽高比的整数倍；无法精确等比时分别向下对齐。
   *
   * @param size 需要计算或发送的画面尺寸。
   * @param scale 应用到媒体宽高的缩放比例。
   * @returns 计算得到的媒体宽高。
   */
  private alignedSize(size: ImageSize, scale: number): ImageSize {
    let divisor: number = size.width;
    let remainder: number = size.height;
    while (remainder !== 0) {
      const next: number = divisor % remainder;
      divisor = remainder;
      remainder = next;
    }
    const alignedScale: number = Math.floor(divisor * scale / 4) * 4;
    if (alignedScale >= 4) {
      return new ImageSize(size.width / divisor * alignedScale, size.height / divisor * alignedScale);
    }
    const width: number = Math.floor(size.width * scale / 4) * 4;
    const height: number = Math.floor(size.height * scale / 4) * 4;
    if (width < 4 || height < 4) {
      throw new XmaxError(XmaxErrorCode.INVALID_CONFIGURATION, 'No aligned video size is available within the size limits');
    }
    return new ImageSize(width, height);
  }

  /**
   * 计算符合模型固定分辨率或像素量约束的输入尺寸。
   *
   * @param size 原始媒体尺寸；宽高必须为有限且大于零的数值。
   * @returns 满足模型固定分辨率或像素量与对齐约束的尺寸。
   * @deprecated 使用 resolveMediaSize 或 resolveGenerationSize 区分媒体帧与生成画布。
   * 固定分辨率必须精确匹配；其他模型按像素量与对齐约束计算尺寸。
   */
  resolveModelInputSize(size: ImageSize): ImageSize {
    const buckets: ImageSize[] = this.model.resolutionBuckets;
    if (buckets.length > 0) {
      if (!buckets.some((bucket: ImageSize): boolean =>
        bucket.width === size.width && bucket.height === size.height)) {
        const supportedSizes: string = buckets.map((bucket: ImageSize): string =>
          `${bucket.width}×${bucket.height}`).join(', ');
        throw new XmaxError(XmaxErrorCode.INVALID_CONFIGURATION,
          `Model ${this.model.name} does not support input resolution ${size.width}×${size.height}. ` +
          `Supported resolutions: ${supportedSizes}`);
      }
      return size;
    }
    const sourceWidth: number = Math.max(Math.round(size.width), 1);
    const sourceHeight: number = Math.max(Math.round(size.height), 1);
    const pixels: number = sourceWidth * sourceHeight;
    if (!Number.isFinite(pixels) || pixels <= 0) {
      throw new XmaxError(XmaxErrorCode.INVALID_CONFIGURATION, 'Image pixel count must be finite and positive');
    }
    let scale: number = 1;
    let rounding: (value: number) => number = Math.round;

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
      return new ImageSize(width, height);
    }
    return this.boundedAlignedSize(sourceWidth * scale, sourceHeight * scale);
  }

  /**
   * 对齐造成面积越界时，选择面积合法且相对目标偏差最小的尺寸。
   *
   * @param width 画面宽度，单位像素。
   * @param height 画面高度，单位像素。
   * @returns 计算得到的媒体宽高。
   */
  private boundedAlignedSize(width: number, height: number): ImageSize {
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
      const distance: number = Math.pow((candidateWidth - width) / width, 2) +
        Math.pow((candidateHeight - height) / height, 2);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestWidth = candidateWidth;
        bestHeight = candidateHeight;
      }
    }
    return new ImageSize(bestWidth, bestHeight);
  }
}
