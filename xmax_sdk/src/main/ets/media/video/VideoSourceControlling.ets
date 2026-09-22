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
   * @param outputWidth 目标视频宽度。
   * @param outputHeight 目标视频高度。
   * @param frameRate 目标视频帧率。
   * @returns 旧视频源释放完成后的 Promise。
   */
  configure(
    filePath: string,
    rotation: VideoRotation,
    outputWidth: number,
    outputHeight: number,
    frameRate: number,
    loop?: boolean
  ): void;

  /**
   * 按共享时间轴开始输出视频帧。
   *
   * @param timeline 音视频共享播放时间轴。
   * @returns 无返回值。
   */
  start(timeline: MediaTimeline): void;

  /** 暂停当前解码器，保留媒体位置与资源。 */
  pause(): void;

  /** 使用统一的暂停时长恢复当前解码器。 */
  resume(pausedDurationUs: number): void;

  /**
   * 停止输出并释放视频文件资源。
   *
   * @returns 视频文件资源释放完成后的 Promise。
   */
  stop(): Promise<void>;
}
