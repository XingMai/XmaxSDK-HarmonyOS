import { VideoRotation } from '../../foundation/media/video/VideoRotation';
import { VideoFrame } from '../../foundation/media/video/VideoFrame';
import { MediaTimeline } from '../MediaTimeline';

export type VideoSourceFrameListener = (frame: VideoFrame) => void;
export type VideoSourceErrorListener = (message: string) => void;

/** 定义本地文件视频轨输出能力。 */
export interface VideoSourceControlling {

  /**
   * 配置待输出的视频轨信息。
   *
   * @param filePath 本地视频文件路径。
   * @param rotation 视频源旋转方向。
   * @param frameRate 目标视频帧率。
   * @returns 无返回值。
   */
  configure(
    filePath: string,
    rotation: VideoRotation,
    frameRate: number
  ): void;

  /**
   * 按共享时间轴开始输出视频帧。
   *
   * @param timeline 音视频共享播放时间轴。
   * @returns 无返回值。
   */
  start(timeline: MediaTimeline): void;

  /**
   * 按新的共享时间轴重新输出视频帧。
   *
   * @param timeline 音视频共享播放时间轴。
   * @returns 无返回值。
   */
  restart(timeline: MediaTimeline): void;

  /**
   * 停止输出并释放视频文件资源。
   *
   * @returns 无返回值。
   */
  stop(): void;
}
