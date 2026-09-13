import { VideoFramePlane } from '../../foundation/media/video/VideoFramePlane';
import { VideoPixelFormat } from '../../foundation/media/video/VideoPixelFormat';
import { VideoRotation } from '../../foundation/media/video/VideoRotation';

/** RTC 后处理后用于显示的视频帧，不包含视图裁剪、镜像或 UI 叠加。 */
export class RealtimeVideoFrame {
  /** 像素宽度，旋转前的缓冲区尺寸。 */
  readonly width: number;
  /** 像素高度，旋转前的缓冲区尺寸。 */
  readonly height: number;
  /** 像素格式；当前远端 Sink 输出 I420。 */
  readonly pixelFormat: VideoPixelFormat;
  /** SDK 独立持有的像素平面；I420 按 Y、U、V 排列，可在回调后继续持有。 */
  readonly planes: VideoFramePlane[];
  /** 实时视频时间轴中的时间戳，单位微秒；不保证从零开始。 */
  readonly timestampUs: number;
  /** 显示时还需顺时针旋转的角度。 */
  readonly rotation: VideoRotation;

  constructor(width: number, height: number, pixelFormat: VideoPixelFormat,
    planes: VideoFramePlane[], timestampUs: number, rotation: VideoRotation) {
    this.width = width;
    this.height = height;
    this.pixelFormat = pixelFormat;
    this.planes = planes.slice();
    this.timestampUs = timestampUs;
    this.rotation = rotation;
  }
}

/** 在 ArkTS 事件循环中按接收顺序异步接收每帧；耗时处理应移交 Worker。 */
export type RealtimeVideoFrameListener = (frame: RealtimeVideoFrame) => void;
