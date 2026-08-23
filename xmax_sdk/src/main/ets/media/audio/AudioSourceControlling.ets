import { MediaTimeline } from '../MediaTimeline';

/** 定义本地文件音频轨输出能力。 */
export interface AudioSourceControlling {

  /**
   * 配置待输出的本地媒体文件。
   *
   * @param filePath 本地媒体文件路径。
   * @returns 无返回值。
   */
  configure(filePath: string): void;

  /**
   * 按共享时间轴开始输出音频帧。
   *
   * @param timeline 音视频共享播放时间轴。
   * @returns 无返回值。
   */
  start(timeline: MediaTimeline): void;

  /**
   * 按新的共享时间轴重新输出音频帧。
   *
   * @param timeline 音视频共享播放时间轴。
   * @returns 无返回值。
   */
  restart(timeline: MediaTimeline): void;

  /**
   * 停止输出并释放音频解码资源。
   *
   * @returns 无返回值。
   */
  stop(): void;
}
