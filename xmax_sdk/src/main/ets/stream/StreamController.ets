//
//  StreamController.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { RealtimeGenerationParameters } from '../service/realtime/RealtimeGenerationOptions';
import { UplinkVideoStatisticsListener, DownlinkVideoStatisticsListener } from '../foundation/rtc/VideoStatistics';
import { QualityConfiguration, QualityChange, AdaptiveQualityListener } from './quality/QualityConfiguration';
import { QualityHistoryStore, MemoryQualityHistoryStore } from './quality/QualityHistory';
import { RealtimeNetworkQuality } from '../service/realtime/RealtimeNetworkQuality';
import { ImageSize } from '../service/media/ImageSize';
import { XmaxLogger } from '../foundation/logging/XmaxLogger';
import { RealtimeTiming } from '../core/realtime/RealtimeTiming';
import { util } from '@kit.ArkTS';
import {
  XmaxError,
  XmaxErrorCode,
  XmaxErrorListener
} from '../foundation/errors/XmaxError';
import { AudioFrame } from '../foundation/media/audio/AudioFrame';
import { VideoFrame } from '../foundation/media/video/VideoFrame';
import { RemoteStream } from '../foundation/rtc/RemoteStream';
import { RtcEventListener } from '../foundation/rtc/RtcEventListener';
import { RtcManaging } from '../foundation/rtc/RtcManaging';
import { RealtimeContext } from '../service/realtime/RealtimeContext';
import { RealtimeNetworkQualityListener } from '../service/realtime/RealtimeNetworkQuality';
import { RealtimePerformanceAlarmListener } from '../service/realtime/RealtimePerformanceAlarm';
import { RealtimePoint } from '../service/realtime/RealtimePoint';
import { RealtimeSessionConnection } from '../service/realtime/RealtimeSessionConnection';
import { RealtimeVideoFormat } from '../service/realtime/RealtimeVideoFormat';
import { EncodingController } from './encoding/EncodingController';
import { EncodingControlling } from './encoding/EncodingControlling';
import { QualityController } from './quality/QualityController';
import { QualityControlling } from './quality/QualityControlling';
import { RoomController } from './room/RoomController';
import { RoomControlling } from './room/RoomControlling';
import { StreamControlling } from './StreamControlling';

const GENERATION_START_TIMEOUT_MS: number = 30000;
const DEFAULT_REMOTE_AUDIO_VOLUME: number = 100;

/**
 * 接收生成结果流的建立或清除通知。
 *
 * @param stream 需要绑定或处理的媒体流。
 * @returns 无返回值。
 */
type RemoteStreamListener = (stream: RemoteStream | null) => void;

/** 保存当前实时生成任务标识，并为外部视频帧生成连续的 SEI 帧序号。 */
class GenerationTask {

  /** 生成任务身份 */
  readonly id: string;

  /** 视频帧 SEI 序号 */
  private frameIndex: number = 0;

  /**
   * 创建生成任务上下文。
   *
   * @param id 生成任务标识。
   * @returns 新建的 GenerationTask 实例。
   */
  constructor(id: string) {
    this.id = id;
  }

  /**
   * 为当前生成任务创建下一帧 SEI，并递增帧序号。
   *
   * @returns 包含任务标识和帧序号的 UTF-8 数据。
   */
  nextSeiData(): Uint8Array {
    const message: string = `${this.id}&index=${this.frameIndex}`;
    this.frameIndex += 1;
    return new util.TextEncoder().encodeInto(message);
  }
}

/** 统一协调 RTC 房间、媒体流、编码和质量事件。 */
export class StreamController implements StreamControlling, RtcEventListener {

  /** RTC 与传输业务组件 */
  private readonly rtcManager: RtcManaging;

  /** 流层组件 */
  private readonly roomController: RoomControlling;
  private readonly encodingController: EncodingControlling;
  private readonly qualityController: QualityControlling;

  /** 远端流与错误通知 */
  private readonly remoteStreamListener: RemoteStreamListener;
  private readonly errorListener: XmaxErrorListener;

  /** 房间及生成服务用户身份 */
  private roomId: string = '';
  private botName: string = '';

  /** 连接与生成耗时记录 */
  private readonly timing: RealtimeTiming;

  /** 本地音频发布状态 */
  private localAudioPublished: boolean = false;

  /** 当前生成任务与结果流 */
  private currentTask: GenerationTask | null = null;
  private activeRemoteStream: RemoteStream | null = null;

  /** 远端音频播放及订阅状态 */
  private remoteAudioActive: boolean = false;
  private remoteAudioVolumePercentage: number = DEFAULT_REMOTE_AUDIO_VOLUME;
  private readonly subscribedRemoteAudioUsers: Set<string> = new Set();

  /** 结果流确认超时与完成通知 */
  private generationStartTimer: number = -1;
  /**
   * 完成当前生成任务的结果流确认等待。
   *
   * @returns 无返回值。
   */
  private generationStartResolve: (() => void) | null = null;
  /**
   * 拒绝当前生成任务的结果流确认等待。
   *
   * @param reason 操作结束原因或平台告警原因。
   * @returns 无返回值。
   */
  private generationStartReject: ((reason: XmaxError) => void) | null = null;

  /**
   * 创建流层统一 Controller 并完成内部组件装配。
   *
   * @param rtcManager 提供 RTC 引擎基础能力的 Manager。
   * @param remoteStreamListener 接收远端视频流变化的监听器。
   * @param errorListener 接收没有对应等待 Promise 的 RTC 异步错误。
   * @param timing 与实时 Manager 共享的启动耗时记录。
   * @param historyStore 保存自动调档历史的数值存储；默认使用内存。
   * @returns 新建的 StreamController 实例。
   */
  constructor(
    rtcManager: RtcManaging,
    remoteStreamListener: RemoteStreamListener,
    errorListener: XmaxErrorListener = (_error: XmaxError): void => {},
    timing: RealtimeTiming = new RealtimeTiming(),
    historyStore: QualityHistoryStore = new MemoryQualityHistoryStore()
  ) {
    this.timing = timing;
    this.rtcManager = rtcManager;
    this.roomController = new RoomController(rtcManager, timing);
    this.encodingController = new EncodingController(rtcManager);
    this.qualityController = new QualityController(rtcManager, historyStore);
    this.remoteStreamListener = remoteStreamListener;
    this.errorListener = errorListener;
    this.rtcManager.setEventListener(this);
  }

  /**
   * 读取当前上下行传输基准与档位。
   *
   * @returns 调档配置；尚未准备时返回 undefined。
   */
  get qualityConfiguration(): QualityConfiguration | undefined { return this.qualityController.qualityConfiguration; }

  /**
   * 根据媒体基准和有效历史档位初始化上下行自动调档。
   *
   * @param baseline 保持原始媒体比例与用户编码选项的视频格式基准。
   * @param model 生成模型名称，用于隔离各模型的历史档位。
   * @returns 初始化后的上下行档位配置。
   */
  prepareQuality(baseline: RealtimeVideoFormat, model: string): QualityConfiguration {
    return this.qualityController.prepareQuality(baseline, model);
  }

  /**
   * 保留上下行档位并替换媒体基准，重置各方向的采样窗口。
   *
   * @param baseline 保持原始媒体比例与用户编码选项的视频格式基准。
   * @returns 更新后的配置；尚未准备时返回 undefined。
   */
  rebaseQuality(baseline: RealtimeVideoFormat): QualityConfiguration | undefined {
    return this.qualityController.rebaseQuality(baseline);
  }

  /**
   * 设置自动调档事件监听器；传入 null 清除监听器。
   *
   * @param listener 接收事件的监听器；可空接口传入 null 时清除监听器。
   * @returns 无返回值。
   */
  setAdaptiveQualityListener(listener: AdaptiveQualityListener | null): void {
    this.qualityController.setAdaptiveQualityListener(listener);
  }

  /**
   * 根据连续网络采样计算上下行建议档位，不直接修改当前档位。
   *
   * @param quality 当前方向或上下行的网络质量采样。
   * @param sampledAt 网络采样的单调时间，单位秒。
   * @returns 各方向的候选档位；无调整建议的方向为 undefined。
   */
  proposeQuality(quality: RealtimeNetworkQuality, sampledAt: number): QualityChange {
    return this.qualityController.proposeQuality(quality, sampledAt);
  }

  /**
   * 记录一次调档提交的结果，仅成功时更新档位和历史。
   *
   * @param downlink 是否为下行方向；false 表示上行。
   * @param level 传输档位，范围 1～5，数值越小质量越高。
   * @param success 此次配置是否已成功提交。
   * @returns 无返回值。
   */
  completeQuality(downlink: boolean, level: number, success: boolean): void {
    this.qualityController.completeQuality(downlink, level, success);
  }

  /**
   * 清空上下行连续采样计数，保留当前档位。
   *
   * @returns 无返回值。
   */
  resetQualitySamples(): void { this.qualityController.resetQualitySamples(); }

  /**
   * 为当前任务提交结果流目标尺寸与码率预算，不等待服务端生效确认。
   *
   * @param taskId 当前生成任务标识。
   * @param targetSize 可选的生成结果流目标尺寸。
   * @returns 无返回值。
   */
  changeTargetSize(taskId: string, targetSize: ImageSize): void {
    if (taskId.length === 0 || this.currentTask?.id !== taskId) {
      throw new XmaxError(XmaxErrorCode.CANCELLED, 'Generation task is no longer active');
    }
    this.roomController.changeTargetSize(taskId, targetSize);
  }

  /**
   * 读取当前活动生成任务的标识。
   *
   * @returns 任务标识；尚未生成时返回空字符串。
   */
  get currentGenerationTaskId(): string {
    return this.currentTask?.id ?? '';
  }

  /**
   * 读取生成结果音频的播放音量。
   *
   * @returns 0～1 的音量比例，0 为静音，1 为原始音量。
   */
  get remoteAudioVolume(): number {
    return this.remoteAudioVolumePercentage / 100;
  }

  /**
   * 设置远端播放音量（0～1），未订阅时缓存到后续订阅。
   *
   * @param volume 音量比例，范围 0～1，0 为静音，1 为原始音量。
   * @returns 无返回值。
   */
  setRemoteAudioVolume(volume: number): void {
    const rtcVolume: number = Math.round(volume * 100);
    this.subscribedRemoteAudioUsers.forEach((userId: string): void => {
      this.rtcManager.setRemoteAudioVolume(userId, rtcVolume);
    });
    this.remoteAudioVolumePercentage = rtcVolume;
  }

  /**
   * 设置实时视频编码器配置。
   *
   * @param videoFormat RTC 视频编码使用的宽度、高度和帧率。
   * @returns 无返回值。
   */
  setVideoEncoderConfig(videoFormat: RealtimeVideoFormat): void {
    this.encodingController.configure(videoFormat);
  }

  /**
   * 设置上行视频统计监听器；传入 null 清除，停止发布或断开时以 undefined 清空统计。
   *
   * @param listener 异步接收上行统计或 undefined 清空通知的监听器；null 表示移除。
   * @returns 无返回值。
   */
  setUplinkVideoStatisticsListener(listener: UplinkVideoStatisticsListener | null): void {
    this.qualityController.setUplinkVideoStatisticsListener(listener);
  }

  /**
   * 设置当前生成流的下行视频统计监听器；传入 null 清除，流清理时以 undefined 清空统计。
   *
   * @param listener 异步接收当前生成流下行统计或 undefined 清空通知的监听器；null 表示移除。
   * @returns 无返回值。
   */
  setDownlinkVideoStatisticsListener(listener: DownlinkVideoStatisticsListener | null): void {
    this.qualityController.setDownlinkVideoStatisticsListener(listener);
  }

  /**
   * 设置网络质量监听器。
   *
   * @param listener 接收网络质量事件的监听器；传入空值时清除监听器。
   * @returns 无返回值。
   */
  setNetworkQualityListener(listener: RealtimeNetworkQualityListener | null): void {
    this.qualityController.setNetworkQualityListener(listener);
  }

  /**
   * 设置设备性能告警监听器。
   *
   * @param listener 接收设备性能事件的监听器；传入空值时清除监听器。
   * @returns 无返回值。
   */
  setPerformanceAlarmListener(listener: RealtimePerformanceAlarmListener | null): void {
    this.qualityController.setPerformanceAlarmListener(listener);
  }

  /**
   * 加入 RTC 房间并发布本地媒体流。
   *
   * @param connection RTC 房间、用户、令牌和目标机器人信息。
   * @param includeLocalAudio 是否随本地视频一起发布本地音频。
   * @param ensureActive 在异步边界确认当前连接操作仍然有效的回调。
   * @returns 操作完成时兑现的 Promise。
   */
  async connect(
    connection: RealtimeSessionConnection,
    includeLocalAudio: boolean,
    ensureActive: () => void
  ): Promise<void> {
    await this.roomController.join(connection, ensureActive);
    ensureActive();
    this.configureRoom(connection.roomId, connection.botName);
    this.publishLocalStream(includeLocalAudio);
  }

  /**
   * 清理媒体流状态并离开当前 RTC 房间；没有活动房间时安全返回。
   *
   * @returns 操作完成时兑现的 Promise。
   */
  async disconnect(): Promise<void> {
    try {
      this.resetStream();
    } finally {
      await this.roomController.leave();
    }
  }

  /**
   * 更新本地音频发布状态。
   *
   * @param enabled 是否发布本地音频。
   * @returns 无返回值。
   */
  setLocalAudioEnabled(enabled: boolean): void {
    if (enabled === this.localAudioPublished) {
      return;
    }

    if (enabled) {
      this.rtcManager.publishLocalAudio();
    } else {
      this.rtcManager.unpublishLocalAudio();
    }

    this.localAudioPublished = enabled;
  }

  /**
   * 推送本地外部视频帧。
   *
   * @param frame 已准备好交给 RTC 的本地视频帧。
   * @returns 无返回值。
   */
  pushLocalVideoFrame(frame: VideoFrame): void {
    const task: GenerationTask | null = this.currentTask;
    this.rtcManager.pushExternalVideoFrame(
      frame,
      task?.nextSeiData()
    );
  }

  /**
   * 推送本地外部音频帧。
   *
   * @param frame 已准备好交给 RTC 的 PCM 音频帧。
   * @returns 无返回值。
   */
  pushLocalAudioFrame(frame: AudioFrame): void {
    if (!this.localAudioPublished) {
      return;
    }

    this.rtcManager.pushExternalAudioFrame(frame);
  }

  /**
   * 建立生成任务、发送开始信令并等待匹配的远端结果流。
   *
   * @param taskId 当前生成任务的唯一标识。
   * @param videoFormat 当前本地媒体使用的视频格式。
   * @param context 当前生成任务使用的条件上下文。
   * @param faceRestoration 是否启用人脸修复。
   * @param targetSize 可选的生成结果流目标尺寸。
   * @param paddingContain 是否保持媒体比例并由服务端补边显示。
   * @param extraParams SDK 内部传递的静态生成配置。
   * @returns 操作完成时兑现的 Promise。
   */
  beginGeneration(
    taskId: string,
    videoFormat: RealtimeVideoFormat,
    context: RealtimeContext,
    faceRestoration: boolean = false,
    targetSize?: ImageSize,
    paddingContain: boolean = false,
    extraParams?: RealtimeGenerationParameters
  ): Promise<void> {
    this.timing.beginSignal(taskId);
    const confirmation: Promise<void> = this.beginGenerationConfirmation(taskId);
    try {
      this.roomController.startGeneration(taskId, videoFormat, context, faceRestoration, targetSize, paddingContain, extraParams);
      this.timing.finishSignal(taskId);
      return confirmation;
    } catch (error) {
      // 只拒绝已创建的等待 Promise，避免另抛异常留下未处理的取消拒绝。
      this.rejectGenerationStart(taskId, XmaxError.from(error));
      return confirmation;
    }
  }

  /**
   * 首帧可用后激活已匹配生成流的远端音频。
   *
   * @returns 无返回值。
   */
  activateRemoteAudio(): void {
    const stream: RemoteStream | null = this.activeRemoteStream;
    if (this.currentTask === null || stream === null) {
      throw new XmaxError(XmaxErrorCode.RTC_ERROR, 'Remote generation audio stream is unavailable');
    }
    this.subscribeRemoteAudio(stream.userId);
    this.remoteAudioActive = true;
  }

  /**
   * 发送生成条件变更信令。
   *
   * @param taskId 当前生成任务的唯一标识。
   * @param videoFormat 当前本地媒体使用的视频格式。
   * @param context 更新后的生成条件上下文。
   * @param faceRestoration 是否启用人脸修复。
   * @param targetSize 可选的生成结果流目标尺寸。
   * @param paddingContain 是否保持媒体比例并由服务端补边显示。
   * @param extraParams SDK 内部传递的静态生成配置。
   * @returns 无返回值。
   */
  updateGeneration(
    taskId: string,
    videoFormat: RealtimeVideoFormat,
    context: RealtimeContext,
    faceRestoration: boolean = false,
    targetSize?: ImageSize,
    paddingContain: boolean = false,
    extraParams?: RealtimeGenerationParameters
  ): void {
    this.roomController.changeGenerationCondition(
      taskId,
      videoFormat,
      context,
      faceRestoration,
      targetSize,
      paddingContain,
      extraParams
    );
  }

  /**
   * 停止生成任务并清理远端结果流。
   *
   * @param taskId 需要停止的生成任务标识；传入空字符串时停止当前任务。
   * @returns 无返回值。
   */
  stopGeneration(taskId: string): void {
    const stoppedTaskId: string = this.stopStreamGeneration(taskId);
    this.roomController.stopGeneration(stoppedTaskId);
  }

  /**
   * 发送生成任务的交互轨迹。
   *
   * @param taskId 接收交互轨迹的生成任务标识。
   * @param points 需要发送的模型输入坐标轨迹点。
   * @returns 无返回值。
   */
  sendTracks(taskId: string, points: RealtimePoint[]): void {
    this.roomController.sendTracks(taskId, points);
  }

  /**
   * 订阅生成端发布的远端音频，由 RTC 内部完成播放。
   *
   * @param userId 远端用户标识。
   * @param published 远端音频是否已发布。
   * @returns 无返回值。
   */
  onRemoteAudioPublished(
    userId: string,
    published: boolean
  ): void {
    if (this.botName.length > 0 && userId !== this.botName) {
      return;
    }

    try {
      if (published && this.remoteAudioActive && this.activeRemoteStream?.userId === userId) {
        this.subscribeRemoteAudio(userId);
      } else if (!published) {
        this.unsubscribeRemoteAudio(userId);
      }
    } catch (error) {
      if (published) {
        this.handleRtcEventError(XmaxError.from(error));
      } else {
        XmaxLogger.error(`${XmaxLogger.localized("清理远端流失败 (Remote Stream Cleanup Failed)\n└─ 原因：", "清理远端流失败 (Remote Stream Cleanup Failed)\n└─ Reason: ")}${XmaxError.from(error).message}`, 'Stream');
      }
    }
  }

  /**
   * 处理远端视频发布状态变化。
   *
   * @param userId 远端用户标识。
   * @param published 远端视频是否已发布。
   * @returns 无返回值。
   */
  onRemoteVideoPublished(
    userId: string,
    published: boolean
  ): void {
    if (this.botName.length > 0 && userId !== this.botName) {
      return;
    }
    try {
      if (!published) {
        if (this.activeRemoteStream?.userId === userId) {
          this.remoteAudioActive = false;
          this.activeRemoteStream = null;
          this.unsubscribeRemoteAudio(userId);
          this.clearRemoteStream();
        }
        return;
      }
      this.rtcManager.subscribeRemoteVideo(userId, true);
    } catch (error) {
      if (published) {
        this.handleRtcEventError(XmaxError.from(error));
      } else {
        XmaxLogger.error(`${XmaxLogger.localized("清理远端流失败 (Remote Stream Cleanup Failed)\n└─ 原因：", "清理远端流失败 (Remote Stream Cleanup Failed)\n└─ Reason: ")}${XmaxError.from(error).message}`, 'Stream');
      }
    }
  }

  /**
   * 根据 SEI 任务标识匹配远端生成流。
   *
   * @param stream 携带 SEI 的远端视频流。
   * @param message 接收到的 SEI 文本。
   * @returns 无返回值。
   */
  onSeiMessageReceived(
    stream: RemoteStream,
    message: string
  ): void {
    const taskId: string = this.currentTask?.id ?? '';
    if (taskId.length === 0 || !this.matchesTaskSei(message, taskId) ||
      stream.roomId !== this.roomId ||
      (this.botName.length > 0 && stream.userId !== this.botName)) {
      return;
    }

    if (this.generationStartResolve === null) {
      return;
    }

    this.timing.matchSEI(taskId);
    try {
      this.remoteStreamListener(stream);
      if (this.currentTask?.id !== taskId) {
        return;
      }
      this.activeRemoteStream = stream;
      this.qualityController.setDownlinkVideoStatisticsUser(stream.userId);
    } catch (error) {
      this.rejectGenerationStart(taskId, XmaxError.from(error));
      return;
    }

    this.resolveGenerationStart(taskId);
  }

  /**
   * 仅用查询参数前的任务标识匹配；os、index 等附加信息不参与任务身份判断。
   *
   * @param message 日志内容、错误说明或收到的信令文本。
   * @param taskId 当前生成任务标识。
   * @returns SEI 中的任务标识与指定任务匹配时返回 true。
   */
  private matchesTaskSei(message: string, taskId: string): boolean {
    const receivedId: string = message.trim().split('?')[0];
    const currentId: string = taskId.split('?')[0];
    return receivedId.length > 0 && receivedId === currentId;
  }

  /**
   * 启动中的订阅错误交给原 Promise 上报，其余异步错误走监听器。
   *
   * @param error 当前操作失败或终止的原因。
   * @returns 无返回值。
   */
  private handleRtcEventError(error: XmaxError): void {
    const taskId: string = this.currentTask?.id ?? '';
    if (taskId.length > 0 &&
      this.generationStartReject !== null) {
      this.rejectGenerationStart(taskId, error);
      return;
    }
    this.errorListener(error);
  }

  /**
   * 订阅指定远端用户的音频，并记录订阅状态。
   *
   * @param userId RTC 用户标识。
   * @returns 无返回值。
   */
  private subscribeRemoteAudio(userId: string): void {
    if (this.subscribedRemoteAudioUsers.has(userId)) {
      return;
    }
    this.rtcManager.setRemoteAudioVolume(userId, this.remoteAudioVolumePercentage);
    this.rtcManager.subscribeRemoteAudio(userId, true);
    this.subscribedRemoteAudioUsers.add(userId);
  }

  /**
   * 取消指定远端用户的音频订阅并清除订阅记录。
   *
   * @param userId RTC 用户标识。
   * @returns 无返回值。
   */
  private unsubscribeRemoteAudio(userId: string): void {
    if (!this.subscribedRemoteAudioUsers.delete(userId)) {
      return;
    }
    try {
      this.rtcManager.subscribeRemoteAudio(userId, false);
    } catch (error) {
      XmaxLogger.error(`${XmaxLogger.localized("取消远端音频订阅失败 (Failed to Unsubscribe Remote Audio)\n└─ 原因：", "取消远端音频订阅失败 (Failed to Unsubscribe Remote Audio)\n└─ Reason: ")}${XmaxError.from(error).message}`, 'Stream');
    }
  }

  /**
   * 配置当前房间及目标远端用户。
   *
   * @param roomId RTC 房间标识。
   * @param botName 服务端生成用户的识别名称。
   * @returns 无返回值。
   */
  private configureRoom(
    roomId: string,
    botName?: string
  ): void {
    this.roomId = roomId;
    this.botName = botName ?? '';
  }

  /**
   * 发布本地视频，并按需发布本地音频。
   *
   * @param includeAudio 是否同时发布本地音频。
   * @returns 无返回值。
   */
  private publishLocalStream(includeAudio: boolean): void {
    this.rtcManager.publishLocalVideo();
    this.qualityController.setUplinkVideoStatisticsEnabled(true);
    if (includeAudio) {
      this.rtcManager.publishLocalAudio();
      this.localAudioPublished = true;
    }
  }

  /**
   * 建立当前生成任务并等待匹配的远端生成流。
   *
   * @param taskId 当前生成任务标识。
   * @returns 操作完成时兑现的 Promise。
   */
  private beginGenerationConfirmation(taskId: string): Promise<void> {
    if (this.currentTask !== null) {
      throw new XmaxError(
        XmaxErrorCode.RTC_ERROR,
        'Realtime generation is already active'
      );
    }

    this.currentTask = new GenerationTask(taskId);
    return this.waitForGenerationStart(taskId);
  }

  /**
   * 停止当前生成任务并取消远端生成流等待。
   *
   * @param taskId 当前生成任务标识。
   * @param reason 操作结束原因或平台告警原因。
   * @returns 实际停止的任务标识；指定任务不匹配或无活动任务时返回空字符串。
   */
  private stopStreamGeneration(
    taskId: string = '',
    reason: string = 'Realtime generation start cancelled'
  ): string {
    const currentTaskId: string = this.currentTask?.id ?? '';
    if (taskId.length > 0 && taskId !== currentTaskId) {
      return '';
    }

    this.qualityController.setAdaptiveQualityListener(null);
    this.qualityController.resetQualitySamples();
    this.rejectGenerationStart(
      currentTaskId,
      new XmaxError(XmaxErrorCode.CANCELLED, reason)
    );
    this.currentTask = null;
    this.activeRemoteStream = null;
    this.remoteAudioActive = false;
    this.subscribedRemoteAudioUsers.forEach((userId: string): void => {
      this.unsubscribeRemoteAudio(userId);
    });
    this.clearRemoteStream();
    return currentTaskId;
  }

  /**
   * 清理当前房间内的本地发布和生成流状态。
   *
   * @returns 无返回值。
   */
  private resetStream(): void {
    this.qualityController.setUplinkVideoStatisticsEnabled(false);
    this.stopStreamGeneration();
    this.qualityController.resetQuality();
    this.localAudioPublished = false;
    this.rtcManager.unpublishLocalVideo();
    this.rtcManager.unpublishLocalAudio();
    this.roomId = '';
    this.botName = '';
  }

  /**
   * 通知监听器清除当前远端生成流。
   *
   * @returns 无返回值。
   */
  private clearRemoteStream(): void {
    this.qualityController.setDownlinkVideoStatisticsUser(undefined);
    this.remoteStreamListener(null);
  }

  /**
   * 创建远端生成流的限时等待。
   *
   * @param taskId 当前生成任务标识。
   * @returns 操作完成时兑现的 Promise。
   */
  private waitForGenerationStart(taskId: string): Promise<void> {
    this.clearGenerationStartWaiter();
    return new Promise((resolve: () => void, reject: (reason: XmaxError) => void) => {
      this.generationStartResolve = resolve;
      this.generationStartReject = reject;
      this.generationStartTimer = setTimeout((): void => {
        this.rejectGenerationStart(
          taskId,
          new XmaxError(XmaxErrorCode.TIMEOUT, 'Realtime generation start timed out')
        );
      }, GENERATION_START_TIMEOUT_MS);
    });
  }

  /**
   * SEI 匹配后立即完成流确认，Core 随后等待真正可用的远端首帧。
   *
   * @param taskId 当前生成任务标识。
   * @returns 无返回值。
   */
  private resolveGenerationStart(taskId: string): void {
    if (this.currentTask?.id !== taskId ||
      this.generationStartResolve === null) {
      return;
    }

    const resolve: () => void = this.generationStartResolve;
    this.clearGenerationStartWaiter();
    resolve();
  }

  /**
   * 拒绝指定生成任务的远端流等待。
   *
   * @param taskId 当前生成任务标识。
   * @param error 当前操作失败或终止的原因。
   * @returns 无返回值。
   */
  private rejectGenerationStart(
    taskId: string,
    error: XmaxError
  ): void {
    if (taskId.length === 0 || this.currentTask?.id !== taskId ||
      this.generationStartReject === null) {
      return;
    }
    const reject: (reason: XmaxError) => void = this.generationStartReject;
    this.clearGenerationStartWaiter();
    reject(error);
  }

  /**
   * 清理远端生成流等待器和超时计时器。
   *
   * @returns 无返回值。
   */
  private clearGenerationStartWaiter(): void {
    if (this.generationStartTimer >= 0) {
      clearTimeout(this.generationStartTimer);
      this.generationStartTimer = -1;
    }
    this.generationStartResolve = null;
    this.generationStartReject = null;
  }
}
