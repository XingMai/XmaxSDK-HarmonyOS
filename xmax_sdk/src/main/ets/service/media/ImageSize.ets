//
//  ImageSize.ets
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
} from '../../foundation/errors/XmaxError';

/** Image or video dimensions, in pixels. */
export class ImageSize {

  /** The width, in pixels. */
  readonly width: number;

  /** The height, in pixels. */
  readonly height: number;

  /**
   * Creates media pixel dimensions.
   *
   * @param width The frame width, in pixels.
   * @param height The frame height, in pixels.
   */
  constructor(
    width: number,
    height: number
  ) {
    if (!Number.isFinite(width) || !Number.isFinite(height) ||
      width <= 0 || height <= 0) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Image width and height must be finite numbers greater than zero'
      );
    }
    this.width = width;
    this.height = height;
  }
}
