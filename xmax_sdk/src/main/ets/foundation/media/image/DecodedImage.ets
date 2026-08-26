import { image } from '@kit.ImageKit';
import {
  XmaxError,
  XmaxErrorCode
} from '../../errors/XmaxError';
import { VideoPixelFormat } from '../video/VideoPixelFormat';
import { ImageVideoFrameData } from './ImageVideoFrameData';

/** 定义 SDK 内部统一使用的已解码图片能力。 */
export interface DecodedImage {

  /** 图片宽度。 */
  readonly width: number;

  /** 图片高度。 */
  readonly height: number;

  /**
   * 居中裁剪并缩放图片，生成指定尺寸的视频帧数据。
   *
   * @param width 目标视频帧宽度。
   * @param height 目标视频帧高度。
   * @returns 可直接装配为视频帧的像素数据。
   */
  makeVideoFrameData(
    width: number,
    height: number
  ): Promise<ImageVideoFrameData>;

  /**
   * 释放已解码图片持有的平台资源。
   *
   * @returns 释放完成后的 Promise。
   */
  release(): Promise<void>;
}

/** 使用 SDK 自有 PixelMap 实现已解码图片。 */
export class PixelMapDecodedImage implements DecodedImage {

  // 平台资源
  private readonly pixelMap: image.PixelMap;

  // 图片信息
  readonly width: number;
  readonly height: number;

  // 运行状态
  private isReleased: boolean = false;

  /**
   * 创建 PixelMap 已解码图片。
   *
   * @param pixelMap 由 SDK 创建并负责释放的可编辑 RGBA PixelMap。
   * @param width 图片宽度。
   * @param height 图片高度。
   */
  constructor(
    pixelMap: image.PixelMap,
    width: number,
    height: number
  ) {
    // 平台资源
    this.pixelMap = pixelMap;

    // 图片信息
    this.width = width;
    this.height = height;
  }

  /**
   * 居中裁剪并缩放图片，生成 RGBA 视频帧数据。
   *
   * @param width 目标视频帧宽度。
   * @param height 目标视频帧高度。
   * @returns 可直接装配为视频帧的像素数据。
   */
  async makeVideoFrameData(
    width: number,
    height: number
  ): Promise<ImageVideoFrameData> {
    this.ensureAvailable();
    this.validateTargetSize(width, height);

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
   * 释放 SDK 持有的 PixelMap。
   *
   * @returns 释放完成后的 Promise。
   */
  async release(): Promise<void> {
    if (this.isReleased) {
      return;
    }

    this.isReleased = true;
    await this.pixelMap.release();
  }

  /** 确认图片资源仍可使用。 */
  private ensureAvailable(): void {
    if (this.isReleased) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Decoded image has already been released'
      );
    }
  }

  /**
   * 校验目标视频帧尺寸。
   *
   * @param width 目标视频帧宽度。
   * @param height 目标视频帧高度。
   */
  private validateTargetSize(width: number, height: number): void {
    if (!Number.isFinite(width) || !Number.isFinite(height) ||
      width <= 0 || height <= 0) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Image width and height must be finite numbers greater than zero'
      );
    }
  }
}
