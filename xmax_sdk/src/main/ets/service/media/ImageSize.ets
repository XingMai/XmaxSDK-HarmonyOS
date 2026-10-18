//
//  ImageSize.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import {
  XmaxError,
  XmaxErrorCode
} from '../../foundation/errors/XmaxError';

/** 以像素为单位描述图片或视频画面的宽高。 */
export class ImageSize {

  /** 媒体像素尺寸 */
  readonly width: number;
  readonly height: number;

  /**
   * 创建媒体像素尺寸。
   *
   * @param width 画面宽度，单位像素。
   * @param height 画面高度，单位像素。
   * @returns 新建的 ImageSize 实例。
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
