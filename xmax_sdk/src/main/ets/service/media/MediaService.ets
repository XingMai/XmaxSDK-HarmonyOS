import { ImageSize } from './ImageSize';
import { MediaServicing } from './MediaServicing';

/** 提供与模型输入约束相关的媒体业务规则。 */
export class MediaService implements MediaServicing {

  // 模型约束
  private static readonly MINIMUM_MODEL_PIXELS: number = 600000;
  private static readonly MAXIMUM_MODEL_PIXELS: number = 1280000;
  private static readonly MODEL_SIZE_ALIGNMENT: number = 32;

  /**
   * 在保持宽高比的前提下计算满足模型像素量与对齐约束的尺寸。
   *
   * @param size 原始媒体尺寸；宽高必须为有限且大于零的数值。
   * @returns 满足模型像素量和 32 像素对齐约束的尺寸。
   */
  resolveModelInputSize(size: ImageSize): ImageSize {
    const pixels: number = size.width * size.height;
    let scale: number = 1;
    let rounding: (value: number) => number = Math.round;

    if (pixels < MediaService.MINIMUM_MODEL_PIXELS) {
      scale = Math.sqrt(MediaService.MINIMUM_MODEL_PIXELS / pixels);
      rounding = Math.ceil;
    } else if (pixels > MediaService.MAXIMUM_MODEL_PIXELS) {
      scale = Math.sqrt(MediaService.MAXIMUM_MODEL_PIXELS / pixels);
      rounding = Math.floor;
    }

    const alignment: number = MediaService.MODEL_SIZE_ALIGNMENT;
    const width: number = Math.max(
      rounding(size.width * scale / alignment) * alignment,
      alignment
    );
    const height: number = Math.max(
      rounding(size.height * scale / alignment) * alignment,
      alignment
    );

    return new ImageSize(width, height);
  }
}
