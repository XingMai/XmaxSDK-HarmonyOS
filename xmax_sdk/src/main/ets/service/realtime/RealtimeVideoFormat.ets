import {
  XmaxError,
  XmaxErrorCode
} from '../../foundation/errors/XmaxError';

export class RealtimeVideoFormat {
  readonly width: number;
  readonly height: number;
  readonly fps: number;

  constructor(
    width: number,
    height: number,
    fps: number
  ) {
    this.width = width;
    this.height = height;
    this.fps = fps;
  }

  validate(): void {
    if (this.width <= 0 || this.height <= 0 || this.fps <= 0 ||
      this.width % 2 !== 0 || this.height % 2 !== 0) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Realtime video width and height must be positive even numbers, and fps must be greater than zero'
      );
    }
  }
}
