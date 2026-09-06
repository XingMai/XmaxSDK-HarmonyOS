import { ImageSize } from './ImageSize';
import { MediaServicing } from './MediaServicing';
import { ModelDefinition, RealtimeModel, RealtimeModels } from '../../core/realtime/RealtimeModel';
import { XmaxError, XmaxErrorCode } from '../../foundation/errors/XmaxError';

/** 提供与模型输入约束相关的媒体业务规则。 */
export class MediaService implements MediaServicing {

  readonly model: ModelDefinition;

  constructor(model: ModelDefinition = RealtimeModels.realtime(RealtimeModel.X2_0)) {
    this.model = model;
  }

  /**
   * 尽量保持宽高比，计算满足当前模型像素量与对齐约束的尺寸。
   *
   * @param size 原始媒体尺寸；宽高必须为有限且大于零的数值。
   * @returns 满足模型像素量和 32 像素对齐约束的尺寸。
   */
  resolveModelInputSize(size: ImageSize): ImageSize {
    const pixels: number = size.width * size.height;
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
      rounding(size.width * scale / alignment) * alignment,
      alignment
    );
    const height: number = Math.max(
      rounding(size.height * scale / alignment) * alignment,
      alignment
    );

    const alignedPixels: number = width * height;
    if (alignedPixels >= this.model.minimumInputPixels && alignedPixels <= this.model.maximumInputPixels) {
      return new ImageSize(width, height);
    }
    return this.boundedAlignedSize(size.width * scale, size.height * scale);
  }

  /** 对齐造成面积越界时，选择面积合法且相对目标偏差最小的尺寸。 */
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
