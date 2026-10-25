//
//  VideoFormat.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import {
  XmaxError,
  XmaxErrorCode
} from '../../errors/XmaxError';
import { VideoPixelFormat } from './VideoPixelFormat';

/** Fixed video dimensions and pixel format. */
export class VideoFormat {

  /** The frame width, in pixels. */
  readonly width: number;

  /** The frame height, in pixels. */
  readonly height: number;

  /** The pixel layout used by the frame buffer. */
  readonly pixelFormat: VideoPixelFormat;

  /**
   * Creates video dimensions and a pixel format.
   *
   * @param width The frame width, in pixels.
   * @param height The frame height, in pixels.
   * @param pixelFormat The media pixel layout.
   */
  constructor(
    width: number,
    height: number,
    pixelFormat: VideoPixelFormat
  ) {
    if (!Number.isFinite(width) || !Number.isFinite(height) ||
      width <= 0 || height <= 0 || Math.floor(width) !== width ||
      Math.floor(height) !== height) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Video width and height must be positive integers'
      );
    }

    this.width = width;
    this.height = height;
    this.pixelFormat = pixelFormat;
  }
}
