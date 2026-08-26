import { image } from '@kit.ImageKit';

/** 定义 SDK 内部使用的平台图片处理能力。 */
export interface ImageManaging {

  /**
   * 居中裁剪并缩放 PixelMap，使其完整填满目标尺寸。
   *
   * @param pixelMap 需要原地处理的 PixelMap。
   * @param targetWidth 目标宽度。
   * @param targetHeight 目标高度。
   * @returns 处理完成后的 Promise。
   */
  resizePixelMapToFill(
    pixelMap: image.PixelMap,
    targetWidth: number,
    targetHeight: number
  ): Promise<void>;
}
