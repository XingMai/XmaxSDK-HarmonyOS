import { AudioFrame } from './AudioFrame';

/** 定义本地 PCM 音频播放能力。 */
export interface AudioManaging {

  /**
   * 创建并启动本地 PCM 音频播放器。
   *
   * @returns 播放器启动完成后的 Promise。
   */
  start(): Promise<void>;

  /**
   * 写入一帧本地预览音频。
   *
   * @param frame 待播放的 PCM 音频帧。
   * @returns 无返回值。
   */
  write(frame: AudioFrame): void;

  /**
   * 启用或暂停本地音频预览，不影响音频帧的其他消费者。
   *
   * @param enabled 是否播放本地预览音频。
   * @returns 无返回值。
   */
  setPlaybackEnabled(enabled: boolean): void;

  /**
   * 清除尚未播放的音频数据。
   *
   * @returns 缓冲区清理完成后的 Promise。
   */
  flush(): Promise<void>;

  /**
   * 停止本地音频播放并释放资源。
   *
   * @returns 播放器停止完成后的 Promise。
   */
  stop(): Promise<void>;
}
