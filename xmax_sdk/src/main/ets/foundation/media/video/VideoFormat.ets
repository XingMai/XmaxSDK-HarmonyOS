import {
  XmaxError,
  XmaxErrorCode
} from '../../errors/XmaxError';
import { VideoPixelFormat } from './VideoPixelFormat';

/** 表示视频帧的固定尺寸和像素格式。 */
export class VideoFormat {
  readonly width: number;
  readonly height: number;
  readonly pixelFormat: VideoPixelFormat;

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
