import { RealtimeVideoFormat } from '../service/realtime/RealtimeVideoFormat';
import { MediaSourceConfiguration } from './MediaSourceConfiguration';

/** 定义本地媒体文件的音视频输入能力。 */
export interface MediaSourceControlling {

  /** 当前媒体文件是否包含可用音轨。 */
  readonly hasAudio: boolean;

  /**
   * 准备本地媒体文件和输出格式。
   *
   * @param filePath 本地媒体文件路径。
   * @param videoFormat 期望的视频输出格式；未传入时根据文件信息自动计算。
   * @returns 文件实际使用的媒体源配置。
   */
  prepare(
    filePath: string,
    videoFormat?: RealtimeVideoFormat
  ): Promise<MediaSourceConfiguration>;

  /**
   * 开始同步输出文件中的音频帧和视频帧。
   *
   * @returns 媒体源启动完成后的 Promise。
   */
  start(): Promise<void>;

  /**
   * 启用或暂停本地音频预览，不影响 RTC 音频帧输出。
   *
   * @param enabled 是否播放本地预览音频。
   * @returns 无返回值。
   */
  setLocalAudioPreviewEnabled(enabled: boolean): void;

  /**
   * 停止输出并释放媒体文件资源。
   *
   * @returns 媒体源停止完成后的 Promise。
   */
  stop(): Promise<void>;
}
