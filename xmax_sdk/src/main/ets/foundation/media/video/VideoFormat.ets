//
//  VideoFormat.ets
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
} from '../../errors/XmaxError';
import { VideoPixelFormat } from './VideoPixelFormat';

/** 表示视频帧的固定尺寸和像素格式。 */
export class VideoFormat {

  /** 画面尺寸与像素格式 */
  readonly width: number;
  readonly height: number;
  readonly pixelFormat: VideoPixelFormat;

  /**
   * 创建视频尺寸与像素格式。
   *
   * @param width 画面宽度，单位像素。
   * @param height 画面高度，单位像素。
   * @param pixelFormat 媒体数据的像素排列格式。
   * @returns 新建的 VideoFormat 实例。
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
