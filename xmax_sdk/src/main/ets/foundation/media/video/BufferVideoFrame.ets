import {
  XmaxError,
  XmaxErrorCode
} from '../../errors/XmaxError';
import { VideoFormat } from './VideoFormat';
import { VideoFrame } from './VideoFrame';
import { VideoFramePlane } from './VideoFramePlane';
import { VideoRotation } from './VideoRotation';

/** 由 ArrayBuffer 持有像素数据的视频帧。 */
export class BufferVideoFrame implements VideoFrame {
  readonly format: VideoFormat;
  readonly timestampUs: number;
  readonly rotation: VideoRotation;
  readonly planes: Array<VideoFramePlane>;

  constructor(
    format: VideoFormat,
    timestampUs: number,
    planes: Array<VideoFramePlane>,
    rotation: VideoRotation = VideoRotation.ROTATION_0
  ) {
    if (!Number.isFinite(timestampUs) || timestampUs < 0) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Video frame timestamp must be a non-negative finite number'
      );
    }
    if (planes.length === 0) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Video frame must contain at least one plane'
      );
    }

    this.format = format;
    this.timestampUs = timestampUs;
    this.rotation = rotation;
    this.planes = planes.slice();
  }
}
