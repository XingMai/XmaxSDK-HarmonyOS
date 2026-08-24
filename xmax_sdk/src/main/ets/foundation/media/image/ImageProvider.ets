import { image } from '@kit.ImageKit';
import {
  XmaxError,
  XmaxErrorCode
} from '../../errors/XmaxError';
import { ImageProviding } from './ImageProviding';

/** 使用 HarmonyOS ImageKit 提供 SDK 内部图片处理能力。 */
export class ImageProvider implements ImageProviding {

  /**
   * 居中裁剪并缩放 PixelMap，使其完整填满目标尺寸。
   *
   * @param pixelMap 需要原地处理的 PixelMap。
   * @param targetWidth 目标宽度。
   * @param targetHeight 目标高度。
   * @returns 处理完成后的 Promise。
   */
  async resizePixelMapToFill(
    pixelMap: image.PixelMap,
    targetWidth: number,
    targetHeight: number
  ): Promise<void> {
    try {
      if (!Number.isFinite(targetWidth) || !Number.isFinite(targetHeight) ||
        targetWidth <= 0 || targetHeight <= 0) {
        throw new XmaxError(
          XmaxErrorCode.INVALID_CONFIGURATION,
          'Image width and height must be finite numbers greater than zero'
        );
      }

      const resolvedTargetWidth: number = Math.max(Math.round(targetWidth), 1);
      const resolvedTargetHeight: number = Math.max(Math.round(targetHeight), 1);
      const info: image.ImageInfo = await pixelMap.getImageInfo();
      const sourceWidth: number = info.size.width;
      const sourceHeight: number = info.size.height;
      const targetAspectRatio: number = resolvedTargetWidth / resolvedTargetHeight;
      const sourceAspectRatio: number = sourceWidth / sourceHeight;

      let cropWidth: number = sourceWidth;
      let cropHeight: number = sourceHeight;
      if (sourceAspectRatio > targetAspectRatio) {
        cropWidth = Math.max(
          Math.floor(sourceHeight * targetAspectRatio),
          1
        );
      } else if (sourceAspectRatio < targetAspectRatio) {
        cropHeight = Math.max(
          Math.floor(sourceWidth / targetAspectRatio),
          1
        );
      }

      if (cropWidth !== sourceWidth || cropHeight !== sourceHeight) {
        await pixelMap.crop({
          x: Math.floor((sourceWidth - cropWidth) / 2),
          y: Math.floor((sourceHeight - cropHeight) / 2),
          size: {
            width: cropWidth,
            height: cropHeight
          }
        });
      }

      if (cropWidth !== resolvedTargetWidth || cropHeight !== resolvedTargetHeight) {
        await pixelMap.scale(
          resolvedTargetWidth / cropWidth,
          resolvedTargetHeight / cropHeight
        );
      }
    } catch (error) {
      throw XmaxError.from(error);
    }
  }
}
