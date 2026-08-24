import { ImageSize } from './ImageSize';
import { ProcessedImage } from './ProcessedImage';

/** 定义图片选择、尺寸处理和编码能力。 */
export interface MediaServicing {

  /**
   * 从系统图库选择一张图片。
   *
   * @returns 所选图片的本地路径。
   */
  pickImage(): Promise<string>;

  /**
   * 计算满足模型输入约束的尺寸。
   *
   * @param size 原始图片尺寸。
   * @returns 满足模型输入约束的尺寸。
   */
  resolveModelInputSize(
    size: ImageSize
  ): ImageSize;

  /**
   * 将图片处理为模型输入尺寸。
   *
   * @param source 图片二进制数据或本地文件路径。
   * @returns 处理后的图片。
   */
  resizeToModelInput(
    source: ArrayBuffer | string
  ): Promise<ProcessedImage>;

  /**
   * 等比缩放图片，使其不超过指定尺寸。
   *
   * @param source 图片二进制数据或本地文件路径。
   * @param maximumSize 最大尺寸。
   * @returns 处理后的图片。
   */
  resizeToFit(
    source: ArrayBuffer | string,
    maximumSize: ImageSize
  ): Promise<ProcessedImage>;

  /**
   * 按指定质量将图片压缩为 JPEG。
   *
   * @param source 图片二进制数据或本地文件路径。
   * @param quality JPEG 压缩质量。
   * @returns 处理后的图片。
   */
  compressJpeg(
    source: ArrayBuffer | string,
    quality: number
  ): Promise<ProcessedImage>;
}
