//
//  VideoFramePlane.ets
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

/** 表示视频帧中的一个像素数据平面。 */
export class VideoFramePlane {

  /** 平面缓冲区与有效字节范围 */
  readonly data: ArrayBuffer;
  readonly stride: number;
  readonly byteOffset: number;
  readonly byteLength: number;

  /**
   * 创建图像平面数据视图。
   *
   * @param data 当前帧的有效媒体数据。
   * @param stride 相邻图像行之间的字节跨度。
   * @param byteOffset 平面数据在缓冲区中的起始字节偏移。
   * @param byteLength 平面有效数据的字节长度。
   * @returns 新建的 VideoFramePlane 实例。
   */
  constructor(
    data: ArrayBuffer,
    stride: number,
    byteOffset: number = 0,
    byteLength: number = data.byteLength - byteOffset
  ) {
    if (data.byteLength === 0 || byteOffset < 0 || byteLength <= 0 ||
      byteOffset + byteLength > data.byteLength) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Video frame plane range is invalid'
      );
    }
    if (!Number.isFinite(stride) || stride <= 0 || Math.floor(stride) !== stride) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Video frame plane stride must be a positive integer'
      );
    }

    this.data = data;
    this.stride = stride;
    this.byteOffset = byteOffset;
    this.byteLength = byteLength;
  }
}
