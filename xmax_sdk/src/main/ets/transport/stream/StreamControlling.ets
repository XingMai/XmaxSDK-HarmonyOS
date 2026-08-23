import { AudioFrame } from '../../foundation/media/audio/AudioFrame';
import { VideoFrame } from '../../foundation/media/video/VideoFrame';

/** 定义 RTC 媒体流发布、推帧和远端流匹配能力。 */
export interface StreamControlling {

  /**
   * 配置当前房间的媒体流信息。
   *
   * @param roomId 房间标识。
   * @param botName 目标远端用户名称。
   * @returns 无返回值。
   */
  configureRoom(
    roomId: string,
    botName?: string
  ): void;

  /**
   * 发布本地媒体流。
   *
   * @param includeAudio 是否同时发布本地音频。
   * @returns 无返回值。
   */
  publishLocalStream(includeAudio: boolean): void;

  /**
   * 更新本地音频的发布状态。
   *
   * @param enabled 是否发布本地音频。
   * @returns 无返回值。
   */
  setLocalAudioEnabled(
    enabled: boolean
  ): void;

  /**
   * 推送本地视频帧。
   *
   * @param frame 本地视频帧。
   * @returns 无返回值。
   */
  pushLocalVideoFrame(
    frame: VideoFrame
  ): void;

  /**
   * 推送本地音频帧。
   *
   * @param frame 本地音频帧。
   * @returns 无返回值。
   */
  pushLocalAudioFrame(
    frame: AudioFrame
  ): void;

  /**
   * 开始等待生成任务对应的远端视频流。
   *
   * @param taskId 生成任务标识。
   * @returns 匹配到远端视频流后的 Promise。
   */
  beginGeneration(
    taskId: string
  ): Promise<void>;

  /**
   * 停止等待生成任务并清理对应远端流。
   *
   * @param taskId 生成任务标识；传入空字符串时停止当前任务。
   * @param reason 停止等待时使用的错误原因。
   * @returns 实际停止的任务标识；没有匹配任务时返回空字符串。
   */
  stopGeneration(
    taskId?: string,
    reason?: string
  ): string;

  /**
   * 清理当前房间的媒体流状态。
   *
   * @returns 无返回值。
   */
  resetRoom(): void;
}
