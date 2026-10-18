//
//  ImageVideoFrameData.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { VideoPixelFormat } from '../video/VideoPixelFormat';

/** 描述已转换为视频帧布局的图片像素数据。 */
export class ImageVideoFrameData {

  /** 图像帧数据与内存布局 */
  /** 视频帧像素数据。 */
  readonly data: ArrayBuffer;

  /** 视频帧宽度。 */
  readonly width: number;

  /** 视频帧高度。 */
  readonly height: number;

  /** 每行像素占用的字节数。 */
  readonly bytesPerRow: number;

  /** 视频帧像素格式。 */
  readonly pixelFormat: VideoPixelFormat;

  /**
   * 创建图片视频帧数据。
   *
   * @param data 视频帧像素数据。
   * @param width 视频帧宽度。
   * @param height 视频帧高度。
   * @param bytesPerRow 每行像素占用的字节数。
   * @param pixelFormat 视频帧像素格式。
   * @returns 新建的 ImageVideoFrameData 实例。
   */
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
