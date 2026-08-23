import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import {
  XmaxError,
  XmaxErrorCode
} from '../../foundation/errors/XmaxError';
import { ImageSize } from './ImageSize';
import { MediaServicing } from './MediaServicing';
import { ProcessedImage } from './ProcessedImage';

/** 提供图片选择、尺寸适配、裁剪缩放和压缩能力。 */
export class MediaService implements MediaServicing {

  private static readonly MINIMUM_MODEL_PIXELS: number = 600000;
  private static readonly MAXIMUM_MODEL_PIXELS: number = 1280000;
  private static readonly MODEL_SIZE_ALIGNMENT: number = 32;
  private static readonly DEFAULT_QUALITY: number = 90;

  /**
   * 从系统图库选择一张图片。
   *
   * @returns 所选图片的本地路径。
   */
  async pickImage(): Promise<string> {
    try {
      const picker: photoAccessHelper.PhotoViewPicker =
        new photoAccessHelper.PhotoViewPicker();
      const options: photoAccessHelper.PhotoSelectOptions =
        new photoAccessHelper.PhotoSelectOptions();

      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;

      const result: photoAccessHelper.PhotoSelectResult = await picker.select(options);
      const selected: string | undefined = result.photoUris[0];

      if (selected === undefined || selected.trim().length === 0) {
        throw new XmaxError(XmaxErrorCode.API_ERROR, 'No image was selected');
      }

      return selected;
    } catch (error) {
      throw XmaxError.from(error);
    }
  }

  /**
   * 在保持宽高比的前提下计算满足模型像素量与对齐约束的尺寸。
   *
   * @param size 原始图片尺寸。
   * @returns 满足模型输入约束的尺寸。
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

  /**
   * 将图片缩放并编码为适合模型输入的图片。
   *
   * @param source 图片二进制数据或本地文件路径。
   * @returns 处理后的图片。
   */
  async resizeToModelInput(
    source: ArrayBuffer | string
  ): Promise<ProcessedImage> {
    const imageSource: image.ImageSource = this.createSource(source);

    try {
      const info: image.ImageInfo = await imageSource.getImageInfo();
      const originalSize: ImageSize = new ImageSize(info.size.width, info.size.height);
      const targetSize: ImageSize = this.resolveModelInputSize(originalSize);

      return await this.resizeAndPack(
        imageSource,
        originalSize,
        targetSize,
        this.normalizedContentType(info.mimeType),
        MediaService.DEFAULT_QUALITY
      );
    } finally {
      await imageSource.release();
    }
  }

  /**
   * 等比缩小图片，使其宽高均不超过指定尺寸。
   *
   * @param source 图片二进制数据或本地文件路径。
   * @param maximumSize 最大尺寸。
   * @returns 处理后的图片。
   */
  async resizeToFit(
    source: ArrayBuffer | string,
    maximumSize: ImageSize
  ): Promise<ProcessedImage> {
    const imageSource: image.ImageSource = this.createSource(source);

    try {
      const info: image.ImageInfo = await imageSource.getImageInfo();
      const originalSize: ImageSize = new ImageSize(info.size.width, info.size.height);
      const targetSize: ImageSize = this.fitSize(originalSize, maximumSize);

      return await this.resizeAndPack(
        imageSource,
        originalSize,
        targetSize,
        this.normalizedContentType(info.mimeType),
        MediaService.DEFAULT_QUALITY
      );
    } finally {
      await imageSource.release();
    }
  }

  /**
   * 居中裁剪并缩放 PixelMap，使其完整填满目标尺寸。
   *
   * @param pixelMap 需要处理的 PixelMap。
   * @param targetSize 目标尺寸。
   * @returns 处理完成后的 Promise。
   */
  async resizePixelMapToFill(
    pixelMap: image.PixelMap,
    targetSize: ImageSize
  ): Promise<void> {
    try {
      const info: image.ImageInfo = await pixelMap.getImageInfo();
      const sourceWidth: number = info.size.width;
      const sourceHeight: number = info.size.height;
      const targetAspectRatio: number = targetSize.width / targetSize.height;
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

      if (cropWidth !== targetSize.width || cropHeight !== targetSize.height) {
        await pixelMap.scale(
          targetSize.width / cropWidth,
          targetSize.height / cropHeight
        );
      }
    } catch (error) {
      throw XmaxError.from(error);
    }
  }

  /**
   * 按指定质量将图片重新编码为 JPEG。
   *
   * @param source 图片二进制数据或本地文件路径。
   * @param quality JPEG 压缩质量，取值范围为 0 至 100。
   * @returns 压缩后的 JPEG 图片。
   */
  async compressJpeg(
    source: ArrayBuffer | string,
    quality: number
  ): Promise<ProcessedImage> {
    this.validateQuality(quality);

    const imageSource: image.ImageSource = this.createSource(source);
    const packer: image.ImagePacker = image.createImagePacker();

    try {
      const info: image.ImageInfo = await imageSource.getImageInfo();
      const data: ArrayBuffer = await packer.packToData(imageSource, {
        format: 'image/jpeg',
        quality: Math.round(quality)
      });

      return new ProcessedImage(
        data,
        new ImageSize(info.size.width, info.size.height),
        'image/jpeg'
      );
    } catch (error) {
      throw XmaxError.from(error);
    } finally {
      try {
        await packer.release();
      } finally {
        await imageSource.release();
      }
    }
  }

  /**
   * 校验图片输入并创建平台图片源。
   *
   * @param source 图片二进制数据或本地文件路径。
   * @returns 创建后的平台图片源。
   */
  private createSource(source: ArrayBuffer | string): image.ImageSource {
    if (typeof source === 'string') {
      if (source.trim().length === 0) {
        throw new XmaxError(
          XmaxErrorCode.INVALID_CONFIGURATION,
          'Image source path must not be empty'
        );
      }

      return image.createImageSource(source);
    }

    if (source.byteLength === 0) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Image source data must not be empty'
      );
    }

    return image.createImageSource(source);
  }

  /**
   * 计算不超过最大尺寸的等比缩放结果。
   *
   * @param source 原始图片尺寸。
   * @param maximum 最大允许尺寸。
   * @returns 等比缩放后的目标尺寸。
   */
  private fitSize(
    source: ImageSize,
    maximum: ImageSize
  ): ImageSize {
    const scale: number = Math.min(
      1,
      maximum.width / source.width,
      maximum.height / source.height
    );

    return new ImageSize(
      Math.max(Math.round(source.width * scale), 1),
      Math.max(Math.round(source.height * scale), 1)
    );
  }

  /**
   * 按目标尺寸缩放图片并编码为受支持的内容类型。
   *
   * @param imageSource 平台图片源。
   * @param sourceSize 原始图片尺寸。
   * @param targetSize 目标图片尺寸。
   * @param requestedContentType 期望的图片内容类型。
   * @param quality 图片编码质量。
   * @returns 处理并编码后的图片。
   */
  private async resizeAndPack(
    imageSource: image.ImageSource,
    sourceSize: ImageSize,
    targetSize: ImageSize,
    requestedContentType: string,
    quality: number
  ): Promise<ProcessedImage> {
    const pixelMap: image.PixelMap = await imageSource.createPixelMap();
    const packer: image.ImagePacker = image.createImagePacker();

    try {
      if (sourceSize.width !== targetSize.width || sourceSize.height !== targetSize.height) {
        await pixelMap.scale(
          targetSize.width / sourceSize.width,
          targetSize.height / sourceSize.height
        );
      }

      const contentType: string = this.supportedContentType(
        requestedContentType,
        packer.supportedFormats
      );

      const data: ArrayBuffer = await packer.packToData(pixelMap, {
        format: contentType,
        quality: quality
      });

      return new ProcessedImage(data, targetSize, contentType);
    } catch (error) {
      throw XmaxError.from(error);
    } finally {
      try {
        await packer.release();
      } finally {
        await pixelMap.release();
      }
    }
  }

  /**
   * 从编码器支持列表中解析实际使用的内容类型。
   *
   * @param requested 期望的图片内容类型。
   * @param supported 编码器支持的内容类型列表。
   * @returns 实际使用的内容类型。
   */
  private supportedContentType(
    requested: string,
    supported: Array<string>
  ): string {
    if (supported.includes(requested)) {
      return requested;
    }

    return 'image/jpeg';
  }

  /**
   * 规范化图片内容类型，并为空值提供 JPEG 默认值。
   *
   * @param contentType 待规范化的内容类型。
   * @returns 规范化后的内容类型。
   */
  private normalizedContentType(contentType: string): string {
    const normalized: string = contentType.trim().toLowerCase();
    return normalized.length === 0 ? 'image/jpeg' : normalized;
  }

  /**
   * 校验 JPEG 压缩质量。
   *
   * @param quality JPEG 压缩质量。
   * @returns 无返回值。
   */
  private validateQuality(quality: number): void {
    if (!Number.isFinite(quality) || quality < 0 || quality > 100) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'JPEG quality must be between 0 and 100'
      );
    }
  }

}
