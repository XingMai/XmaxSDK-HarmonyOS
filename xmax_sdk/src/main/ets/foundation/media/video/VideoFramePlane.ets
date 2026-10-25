//
//  VideoFramePlane.ets
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

/** A pixel data plane in a video frame. */
export class VideoFramePlane {

  /** The buffer containing this plane's pixel bytes. */
  readonly data: ArrayBuffer;

  /** The plane row stride, in bytes. */
  readonly stride: number;

  /** The plane's starting byte offset within its buffer. */
  readonly byteOffset: number;

  /** The plane's valid byte count. */
  readonly byteLength: number;

  /**
   * Creates an image plane view.
   *
   * @param data The pixel buffer backing this plane, retained without copying.
   * @param stride The image row stride, in bytes.
   * @param byteOffset The plane's starting byte offset within the buffer.
   * @param byteLength The plane's valid byte length.
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
