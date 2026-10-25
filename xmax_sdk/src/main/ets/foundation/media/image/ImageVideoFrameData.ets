//
//  ImageVideoFrameData.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { VideoPixelFormat } from '../video/VideoPixelFormat';

/** Image pixels arranged as a video frame. */
export class ImageVideoFrameData {

  /** The video frame pixels. */
  readonly data: ArrayBuffer;

  /** The video frame width. */
  readonly width: number;

  /** The video frame height. */
  readonly height: number;

  /** The pixel row stride, in bytes. */
  readonly bytesPerRow: number;

  /** The video pixel format. */
  readonly pixelFormat: VideoPixelFormat;

  /** Creates image-backed video frame data. */
  constructor(
    data: ArrayBuffer,
    width: number,
    height: number,
    bytesPerRow: number,
    pixelFormat: VideoPixelFormat
  ) {
    this.data = data;
    this.width = width;
    this.height = height;
    this.bytesPerRow = bytesPerRow;
    this.pixelFormat = pixelFormat;
  }
}
