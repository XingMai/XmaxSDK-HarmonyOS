import { image } from '@kit.ImageKit';
import { DecodedImage } from './DecodedImage';

/** 定义 SDK 内部使用的平台图片处理能力。 */
export interface ImageManaging {

  /**
   * 解码图片编码数据。
   *
   * @param data 完整的图片编码数据。
   * @returns 由 SDK 持有的已解码图片。
   */
  decode(data: ArrayBuffer | Uint8Array): Promise<DecodedImage>;

  /**
   * 解码本地图片文件。
   *
   * @param filePath 可读取的本地图片文件路径。
   * @returns 由 SDK 持有的已解码图片。
   */
  decodeFile(filePath: string): Promise<DecodedImage>;

  /**
   * 为平台 PixelMap 创建不影响调用方所有权的已解码图片快照。
   *
   * @param pixelMap 接入方持有的 PixelMap；SDK 不会修改或释放该对象。
   * @returns 由 SDK 持有的已解码图片。
   */
  decodePixelMap(pixelMap: image.PixelMap): Promise<DecodedImage>;
}
