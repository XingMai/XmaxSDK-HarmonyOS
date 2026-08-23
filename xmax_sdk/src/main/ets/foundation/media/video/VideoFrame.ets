import { VideoFormat } from './VideoFormat';
import { VideoFramePlane } from './VideoFramePlane';
import { VideoRotation } from './VideoRotation';

/** 表示由视频源持有的中性视频帧。 */
export interface VideoFrame {
  /** 视频帧格式。 */
  readonly format: VideoFormat;

  /** 视频帧时间戳，单位为微秒。 */
  readonly timestampUs: number;

  /** 视频帧顺时针旋转角度。 */
  readonly rotation: VideoRotation;

  /** 按像素格式约定排列的数据平面。 */
  readonly planes: Array<VideoFramePlane>;
}
