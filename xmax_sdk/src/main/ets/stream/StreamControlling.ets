import { AudioFrame } from '../foundation/media/audio/AudioFrame';
import { VideoFrame } from '../foundation/media/video/VideoFrame';
import { RealtimeContext } from '../service/realtime/RealtimeContext';
import { RealtimeNetworkQualityListener } from '../service/realtime/RealtimeNetworkQuality';
import { RealtimePerformanceAlarmListener } from '../service/realtime/RealtimePerformanceAlarm';
import { RealtimePoint } from '../service/realtime/RealtimePoint';
import { RealtimeSessionConnection } from '../service/realtime/RealtimeSessionConnection';
import { RealtimeVideoFormat } from '../service/realtime/RealtimeVideoFormat';

/** 定义流层向 Core 和其他业务层暴露的统一能力。 */
export interface StreamControlling {

  /**
   * 设置实时视频编码器配置。
   *
   * @param videoFormat RTC 视频编码使用的宽度、高度和帧率。
   * @returns 无返回值。
   */
  setVideoEncoderConfig(videoFormat: RealtimeVideoFormat): void;

  /**
   * 设置网络质量监听器。
   *
   * @param listener 接收网络质量事件的监听器；传入空值时清除监听器。
   * @returns 无返回值。
   */
  setNetworkQualityListener(listener: RealtimeNetworkQualityListener | null): void;

  /**
   * 设置设备性能告警监听器。
   *
   * @param listener 接收设备性能事件的监听器；传入空值时清除监听器。
   * @returns 无返回值。
   */
  setPerformanceAlarmListener(listener: RealtimePerformanceAlarmListener | null): void;

  /**
   * 加入 RTC 房间并发布本地媒体流。
   *
   * @param connection RTC 房间、用户、令牌和目标机器人信息。
   * @param includeLocalAudio 是否随本地视频一起发布本地音频。
   * @param ensureActive 在异步边界确认当前连接操作仍然有效的回调。
   * @returns 进房和本地流发布完成后的 Promise。
   */
  connect(
    connection: RealtimeSessionConnection,
    includeLocalAudio: boolean,
    ensureActive: () => void
  ): Promise<void>;

  /**
   * 清理媒体流状态并离开当前 RTC 房间；没有活动房间时安全返回。
   *
   * @returns 流资源清理完成后的 Promise。
   */
  disconnect(): Promise<void>;

  /**
   * 更新本地音频发布状态。
   *
   * @param enabled 是否发布本地音频。
   * @returns 无返回值。
   */
  setLocalAudioEnabled(enabled: boolean): void;

  /**
   * 推送本地外部视频帧。
   *
   * @param frame 已准备好交给 RTC 的本地视频帧。
   * @returns 无返回值。
   */
  pushLocalVideoFrame(frame: VideoFrame): void;

  /**
   * 推送本地外部音频帧。
   *
   * @param frame 已准备好交给 RTC 的 PCM 音频帧。
   * @returns 无返回值。
   */
  pushLocalAudioFrame(frame: AudioFrame): void;

  /**
   * 建立生成任务、发送开始信令并等待匹配的远端结果流。
   *
   * @param taskId 当前生成任务的唯一标识。
   * @param videoFormat 当前本地媒体使用的视频格式。
   * @param context 当前生成任务使用的条件上下文。
   * @returns 匹配到远端结果流后的 Promise。
   */
  beginGeneration(
    taskId: string,
    videoFormat: RealtimeVideoFormat,
    context: RealtimeContext
  ): Promise<void>;

  /**
   * 发送生成条件变更信令。
   *
   * @param taskId 当前生成任务的唯一标识。
   * @param videoFormat 当前本地媒体使用的视频格式。
   * @param context 更新后的生成条件上下文。
   * @returns 无返回值。
   */
  updateGeneration(
    taskId: string,
    videoFormat: RealtimeVideoFormat,
    context: RealtimeContext
  ): void;

  /**
   * 停止生成任务并清理远端结果流。
   *
   * @param taskId 需要停止的生成任务标识；传入空字符串时停止当前任务。
   * @returns 无返回值。
   */
  stopGeneration(taskId: string): void;

  /**
   * 发送生成任务的交互轨迹。
   *
   * @param taskId 接收交互轨迹的生成任务标识。
   * @param points 需要发送的模型输入坐标轨迹点。
   * @returns 无返回值。
   */
  sendTracks(taskId: string, points: RealtimePoint[]): void;
}
