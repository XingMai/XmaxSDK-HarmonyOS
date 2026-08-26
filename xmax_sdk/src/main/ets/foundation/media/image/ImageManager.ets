import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import {
  XmaxError,
  XmaxErrorCode
} from '../../errors/XmaxError';
import {
  DecodedImage,
  PixelMapDecodedImage
} from './DecodedImage';
import { ImageManaging } from './ImageManaging';

/** 使用 HarmonyOS ImageKit 提供 SDK 内部图片解码能力。 */
export class ImageManager implements ImageManaging {

  /**
   * 解码图片编码数据。
   *
   * @param data 完整的图片编码数据。
   * @returns 由 SDK 持有的已解码图片。
   */
  async decode(data: ArrayBuffer | Uint8Array): Promise<DecodedImage> {
    let encodedData: ArrayBuffer;
    if (data instanceof Uint8Array) {
      encodedData = new ArrayBuffer(data.byteLength);
      new Uint8Array(encodedData).set(data);
    } else {
      encodedData = data;
    }
    if (encodedData.byteLength === 0) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Image data must not be empty'
      );
    }

    let imageSource: image.ImageSource | undefined = undefined;
    try {
      imageSource = image.createImageSource(encodedData);
      return await this.decodeSource(imageSource);
    } catch (error) {
      throw XmaxError.from(error);
    } finally {
      if (imageSource !== undefined) {
        await imageSource.release();
      }
    }
  }

  /**
   * 解码本地图片文件。
   *
   * @param filePath 可读取的本地图片文件路径。
   * @returns 由 SDK 持有的已解码图片。
   */
  async decodeFile(filePath: string): Promise<DecodedImage> {
    if (filePath.trim().length === 0) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Local image file path must not be empty'
      );
    }

    const sourceFile: fileIo.File = fileIo.openSync(
      filePath,
      fileIo.OpenMode.READ_ONLY
    );
    let imageSource: image.ImageSource | undefined = undefined;

    try {
      imageSource = image.createImageSource(sourceFile.fd);
      return await this.decodeSource(imageSource);
    } catch (error) {
      throw XmaxError.from(error);
    } finally {
      try {
        if (imageSource !== undefined) {
          await imageSource.release();
        }
      } finally {
        fileIo.closeSync(sourceFile);
      }
    }
  }

  /**
   * 为平台 PixelMap 创建不影响调用方所有权的已解码图片快照。
   *
   * @param pixelMap 接入方持有的 PixelMap；SDK 不会修改或释放该对象。
   * @returns 由 SDK 持有的已解码图片。
   */
  async decodePixelMap(pixelMap: image.PixelMap): Promise<DecodedImage> {
    let snapshot: image.PixelMap | null = null;

    try {
      const info: image.ImageInfo = await pixelMap.getImageInfo();
      const pixelData: ArrayBuffer = new ArrayBuffer(
        pixelMap.getPixelBytesNumber()
      );
      await pixelMap.readPixelsToBuffer(pixelData);
      snapshot = await image.createPixelMap(pixelData, {
        size: info.size,
        srcPixelFormat: info.pixelFormat,
        pixelFormat: image.PixelMapFormat.RGBA_8888,
        editable: true,
        alphaType: info.alphaType
      });

      const normalizedInfo: image.ImageInfo = await snapshot.getImageInfo();
      const decodedImage: DecodedImage = new PixelMapDecodedImage(
        snapshot,
        normalizedInfo.size.width,
        normalizedInfo.size.height
      );
      snapshot = null;
      return decodedImage;
    } catch (error) {
      throw XmaxError.from(error);
    } finally {
      if (snapshot !== null) {
        await snapshot.release();
      }
    }
  }

  /**
   * 将 ImageSource 解码为 SDK 自有的 RGBA PixelMap。
   *
   * @param imageSource 待解码的 ImageKit 图片源。
   * @returns 由 SDK 持有的已解码图片。
   */
  private async decodeSource(
    imageSource: image.ImageSource
  ): Promise<DecodedImage> {
    const pixelMap: image.PixelMap = await imageSource.createPixelMap({
      editable: true,
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888
    });

    try {
      const info: image.ImageInfo = await pixelMap.getImageInfo();
      return new PixelMapDecodedImage(
        pixelMap,
        info.size.width,
        info.size.height
      );
    } catch (error) {
      await pixelMap.release();
      throw XmaxError.from(error);
    }
  }
}
