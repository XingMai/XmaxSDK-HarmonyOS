//
//  StreamControlling.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { UplinkVideoStatisticsListener, DownlinkVideoStatisticsListener } from '../foundation/rtc/VideoStatistics';
import { QualityConfiguration, QualityChange, AdaptiveQualityListener } from './quality/QualityConfiguration';
import { RealtimeNetworkQuality } from '../service/realtime/RealtimeNetworkQuality';
import { ImageSize } from '../service/media/ImageSize';
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
   * 设置上行视频统计监听器；传入 null 清除，停止发布或断开时以 undefined 清空统计。
   *
   * @param listener 异步接收上行统计或 undefined 清空通知的监听器；null 表示移除。
   * @returns 无返回值。
   */
  setUplinkVideoStatisticsListener(listener: UplinkVideoStatisticsListener | null): void;

  /**
   * 设置当前生成流的下行视频统计监听器；传入 null 清除，流清理时以 undefined 清空统计。
   *
   * @param listener 异步接收当前生成流下行统计或 undefined 清空通知的监听器；null 表示移除。
   * @returns 无返回值。
   */
  setDownlinkVideoStatisticsListener(listener: DownlinkVideoStatisticsListener | null): void;

  /** 自动传输档位状态 */
  readonly qualityConfiguration: QualityConfiguration | undefined;

  /**
   * 根据媒体基准和有效历史档位初始化上下行自动调档。
   *
   * @param baseline 保持原始媒体比例与用户编码选项的视频格式基准。
   * @param model 生成模型名称，用于隔离各模型的历史档位。
   * @returns 初始化后的上下行档位配置。
   */
  prepareQuality(baseline: RealtimeVideoFormat, model: string): QualityConfiguration;

  /**
   * 保留上下行档位并替换媒体基准，重置各方向的采样窗口。
   *
   * @param baseline 保持原始媒体比例与用户编码选项的视频格式基准。
   * @returns 更新后的配置；尚未准备时返回 undefined。
   */
  rebaseQuality(baseline: RealtimeVideoFormat): QualityConfiguration | undefined;

  /**
   * 设置自动调档事件监听器；传入 null 清除监听器。
   *
   * @param listener 接收事件的监听器；可空接口传入 null 时清除监听器。
   * @returns 无返回值。
   */
  setAdaptiveQualityListener(listener: AdaptiveQualityListener | null): void;

  /**
   * 根据连续网络采样计算上下行建议档位，不直接修改当前档位。
   *
   * @param quality 当前方向或上下行的网络质量采样。
   * @param sampledAt 网络采样的单调时间，单位秒。
   * @returns 各方向的候选档位；无调整建议的方向为 undefined。
   */
  proposeQuality(quality: RealtimeNetworkQuality, sampledAt: number): QualityChange;

  /**
   * 记录一次调档提交的结果，仅成功时更新档位和历史。
   *
   * @param downlink 是否为下行方向；false 表示上行。
   * @param level 传输档位，范围 1～5，数值越小质量越高。
   * @param success 此次配置是否已成功提交。
   * @returns 无返回值。
   */
  completeQuality(downlink: boolean, level: number, success: boolean): void;

  /**
   * 清空上下行连续采样计数，保留当前档位。
   *
   * @returns 无返回值。
   */
  resetQualitySamples(): void;

  /**
   * 为当前任务提交结果流目标尺寸与码率预算，不等待服务端生效确认。
   *
   * @param taskId 当前生成任务标识。
   * @param targetSize 可选的生成结果流目标尺寸。
   * @returns 无返回值。
   */
  changeTargetSize(taskId: string, targetSize: ImageSize): void;

  /** 远端音频播放音量 */
  /** 当前远端播放音量（0～1），按 RTC 百分比精度返回。 */
  readonly remoteAudioVolume: number;

  /**
   * 设置远端播放音量（0～1），未订阅时缓存到后续订阅。
   *
   * @param volume 0～1 的有限数值；0 为静音，1 为原始音量；尚未创建本地流时为 1。
   * @returns 无返回值。
   */
  setRemoteAudioVolume(volume: number): void;

  /** 当前生成任务身份 */
  /** @returns 正在启动或运行的生成任务标识；没有任务时为空字符串。 */
  readonly currentGenerationTaskId: string;

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
   * @param faceRestoration 是否启用人脸修复。
   * @param targetSize 可选的生成结果流目标尺寸。
   * @param paddingContain 是否保持媒体比例并由服务端补边显示。
   * @returns 匹配到远端结果流后的 Promise。
   */
  beginGeneration(
    taskId: string,
    videoFormat: RealtimeVideoFormat,
    context: RealtimeContext,
    faceRestoration?: boolean,
    targetSize?: ImageSize,
    paddingContain?: boolean
  ): Promise<void>;

  /**
   * 首帧可用后激活已匹配生成流的远端音频。
   *
   * @returns 无返回值。
   */
  activateRemoteAudio(): void;

  /**
   * 发送生成条件变更信令。
   *
   * @param taskId 当前生成任务的唯一标识。
   * @param videoFormat 当前本地媒体使用的视频格式。
   * @param context 更新后的生成条件上下文。
   * @param faceRestoration 是否启用人脸修复。
   * @param targetSize 可选的生成结果流目标尺寸。
   * @param paddingContain 是否保持媒体比例并由服务端补边显示。
   * @returns 无返回值。
   */
  updateGeneration(
    taskId: string,
    videoFormat: RealtimeVideoFormat,
    context: RealtimeContext,
    faceRestoration?: boolean,
    targetSize?: ImageSize,
    paddingContain?: boolean
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
