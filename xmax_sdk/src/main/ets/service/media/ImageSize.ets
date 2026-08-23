import {
  XmaxError,
  XmaxErrorCode
} from '../../foundation/errors/XmaxError';

export class ImageSize {
  readonly width: number;
  readonly height: number;

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
    this.width = Math.max(Math.round(width), 1);
    this.height = Math.max(Math.round(height), 1);
  }
}
