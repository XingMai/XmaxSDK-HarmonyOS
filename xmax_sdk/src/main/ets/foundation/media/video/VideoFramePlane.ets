import {
  XmaxError,
  XmaxErrorCode
} from '../../errors/XmaxError';

/** 表示视频帧中的一个像素数据平面。 */
export class VideoFramePlane {
  readonly data: ArrayBuffer;
  readonly stride: number;
  readonly byteOffset: number;
  readonly byteLength: number;

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
