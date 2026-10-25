//
//  DecodedImage.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { image } from '@kit.ImageKit';
import {
  XmaxError,
  XmaxErrorCode
} from '../../errors/XmaxError';
import { VideoPixelFormat } from '../video/VideoPixelFormat';
import { ImageVideoFrameData } from './ImageVideoFrameData';

/** An interface for a decoded image owned by XmaxSDK. */
export interface DecodedImage {

  /** The image width. */
  readonly width: number;

  /** The image height. */
  readonly height: number;

  /**
   * Crops centrally and scales an image into video frame data.
   *
   * @param width The target video frame width.
   * @param height The target video frame height.
   *
   * @returns The pixels for creating a video frame.
   */
  makeVideoFrameData(
    width: number,
    height: number
  ): Promise<ImageVideoFrameData>;

  /**
   * Releases platform resources held by the decoded image.
   *
   * The Promise fulfills after release completes.
   */
  release(): Promise<void>;
}

/** A decoded image backed by an SDK-owned PixelMap. */
export class PixelMapDecodedImage implements DecodedImage {

  /** The SDK-owned editable image resource. */
  private readonly pixelMap: image.PixelMap;

  /** The decoded image width, in pixels. */
  readonly width: number;

  /** The decoded image height, in pixels. */
  readonly height: number;

  /** Whether the owned resource has been released. */
  private isReleased: boolean = false;

  /** Creates a decoded PixelMap image. */
  constructor(
    pixelMap: image.PixelMap,
    width: number,
    height: number
  ) {
    // Platform resources
    this.pixelMap = pixelMap;

    // Image information
    this.width = width;
    this.height = height;
  }

  /**
   * Crops centrally and scales an image into RGBA frame data.
   *
   * @param width The target video frame width.
   * @param height The target video frame height.
   *
   * @returns The pixels for creating a video frame.
   */
  async makeVideoFrameData(
    width: number,
    height: number
  ): Promise<ImageVideoFrameData> {
    this.ensureAvailable();
    this.validateTargetSize(
      width,
      height
    );

    try {
      const targetWidth: number = Math.max(Math.round(width), 1);
      const targetHeight: number = Math.max(Math.round(height), 1);
      const targetAspectRatio: number = targetWidth / targetHeight;
      const sourceAspectRatio: number = this.width / this.height;

      let cropWidth: number = this.width;
      let cropHeight: number = this.height;
      if (sourceAspectRatio > targetAspectRatio) {
        cropWidth = Math.max(Math.floor(this.height * targetAspectRatio), 1);
      } else if (sourceAspectRatio < targetAspectRatio) {
        cropHeight = Math.max(Math.floor(this.width / targetAspectRatio), 1);
      }

      if (cropWidth !== this.width || cropHeight !== this.height) {
        await this.pixelMap.crop({
          x: Math.floor((this.width - cropWidth) / 2),
          y: Math.floor((this.height - cropHeight) / 2),
          size: {
            width: cropWidth,
            height: cropHeight
          }
        });
      }

      if (cropWidth !== targetWidth || cropHeight !== targetHeight) {
        await this.pixelMap.scale(
          targetWidth / cropWidth,
          targetHeight / cropHeight
        );
      }

      const info: image.ImageInfo = await this.pixelMap.getImageInfo();
      const frameData: ArrayBuffer = new ArrayBuffer(
        this.pixelMap.getPixelBytesNumber()
      );
      await this.pixelMap.readPixelsToBuffer(frameData);

      return new ImageVideoFrameData(
        frameData,
        info.size.width,
        info.size.height,
        this.pixelMap.getBytesNumberPerRow(),
        VideoPixelFormat.RGBA
      );
    } catch (error) {
      throw XmaxError.from(error);
    }
  }

  /**
   * Releases the SDK-owned PixelMap.
   *
   * The Promise fulfills after release completes.
   */
  async release(): Promise<void> {
    if (this.isReleased) {
      return;
    }

    this.isReleased = true;
    await this.pixelMap.release();
  }

  /** Verifies that image resources are still usable. */
  private ensureAvailable(): void {
    if (this.isReleased) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Decoded image has already been released'
      );
    }
  }

  /**
   * Validates the target video frame dimensions.
   *
   * @param width The target video frame width.
   * @param height The target video frame height.
   */
  private validateTargetSize(
    width: number,
    height: number
  ): void {
    if (!Number.isFinite(width) || !Number.isFinite(height) ||
      width <= 0 || height <= 0) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Image width and height must be finite numbers greater than zero'
      );
    }
  }
}
