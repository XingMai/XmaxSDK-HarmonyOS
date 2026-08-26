import { image } from '@kit.ImageKit';
import { VideoFrame } from '../../foundation/media/video/VideoFrame';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';

export type ImageSourceFrameListener = (frame: VideoFrame) => void;
export type ImageSourceErrorListener = (message: string) => void;

/** 定义本地图片持续输出视频帧的能力。 */
export interface ImageSourceControlling {

  /**
   * 准备图片和输出格式。
   *
   * @param source 本地文件路径、图片编码数据或平台 PixelMap。
   * @param videoFormat 期望的视频输出格式；未传入时根据图片尺寸自动计算。
   * @returns 图片实际使用的视频输出格式。
   */
  prepare(
    source: string | ArrayBuffer | Uint8Array | image.PixelMap,
    videoFormat?: RealtimeVideoFormat
  ): Promise<RealtimeVideoFormat>;

  /**
   * 开始按目标帧率持续输出图片帧。
   *
   * @returns 无返回值。
   */
  start(): void;

  /**
   * 停止输出并释放图片资源。
   *
   * @returns 无返回值。
   */
  stop(): void;
}
