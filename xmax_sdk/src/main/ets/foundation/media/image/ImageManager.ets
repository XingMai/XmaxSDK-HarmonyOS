//
//  ImageManager.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

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

/** An ImageKit-backed image decoder for SDK media. */
export class ImageManager implements ImageManaging {

  /**
   * Decodes encoded image data.
   *
   * @param data The complete encoded image bytes.
   *
   * @returns The decoded image owned by XmaxSDK.
   */
  async decode(
    data: ArrayBuffer | Uint8Array
  ): Promise<DecodedImage> {
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
   * Decodes a local image file.
   *
   * @param filePath The readable local image file path.
   *
   * @returns The decoded image owned by XmaxSDK.
   */
  async decodeFile(
    filePath: string
  ): Promise<DecodedImage> {
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
   * Snapshots a PixelMap without changing caller ownership.
   *
   * @param pixelMap The caller-owned PixelMap, which XmaxSDK neither modifies nor releases.
   *
   * @returns The decoded image owned by XmaxSDK.
   */
  async decodePixelMap(
    pixelMap: image.PixelMap
  ): Promise<DecodedImage> {
    let snapshot: image.PixelMap | null = null;

    try {
      const info: image.ImageInfo = await pixelMap.getImageInfo();
      const pixelData: ArrayBuffer = new ArrayBuffer(
        pixelMap.getPixelBytesNumber()
      );
      await pixelMap.readPixelsToBuffer(pixelData);
      snapshot = await image.createPixelMap(
        pixelData,
        {
          size: info.size,
          srcPixelFormat: info.pixelFormat,
          pixelFormat: image.PixelMapFormat.RGBA_8888,
          editable: true,
          alphaType: info.alphaType
        }
      );

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
   * Decodes an ImageSource into an SDK-owned RGBA PixelMap.
   *
   * @param imageSource The ImageKit source to decode.
   *
   * @returns The decoded image owned by XmaxSDK.
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
