import { util } from '@kit.ArkTS';
import {
  XmaxError,
  XmaxErrorCode
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
const GENERATION_START_DELAY_MS: number = 150;
type RemoteStreamListener = (stream: RemoteStream | null) => void;

/** 保存当前实时生成任务标识及对应的 SEI 数据。 */
class GenerationTask {

  readonly id: string;
  readonly seiData: Uint8Array;

  /**
   * 创建生成任务上下文。
   *
   * @param id 生成任务标识。
   */
  constructor(id: string) {
    this.id = id;
    this.seiData = new util.TextEncoder().encodeInto(id);
  }
}

/** 统一协调 RTC 房间、媒体流、编码和质量事件。 */
export class StreamController implements StreamControlling, RtcEventListener {

  // 基础层组件
  private readonly rtcManager: RtcManaging;

  // 流层组件
  private readonly roomController: RoomControlling;
  private readonly encodingController: EncodingControlling;
  private readonly qualityController: QualityControlling;

  // 事件监听
  private readonly remoteStreamListener: RemoteStreamListener;

  // 房间资源
  private roomId: string = '';
  private botName: string = '';

  // 本地流状态
  private localAudioPublished: boolean = false;

  // 生成状态
  private currentTask: GenerationTask | null = null;
  private generationStartTimer: number = -1;
  private generationStartResolve: (() => void) | null = null;
  private generationStartReject: ((reason: XmaxError) => void) | null = null;

  /**
   * 创建流层统一 Controller 并完成内部组件装配。
   *
   * @param rtcManager 提供 RTC 引擎基础能力的 Manager。
   * @param remoteStreamListener 接收远端视频流变化的监听器。
   */
  constructor(
    rtcManager: RtcManaging,
    remoteStreamListener: RemoteStreamListener
  ) {
    this.rtcManager = rtcManager;
    this.roomController = new RoomController(rtcManager);
    this.encodingController = new EncodingController(rtcManager);
    this.qualityController = new QualityController(rtcManager);
    this.remoteStreamListener = remoteStreamListener;
    this.rtcManager.setEventListener(this);
  }

  /** @inheritdoc */
  setVideoEncoderConfig(videoFormat: RealtimeVideoFormat): void {
    this.encodingController.configure(videoFormat);
  }

  /** @inheritdoc */
  setNetworkQualityListener(listener: RealtimeNetworkQualityListener | null): void {
    this.qualityController.setNetworkQualityListener(listener);
  }

  /** @inheritdoc */
  setPerformanceAlarmListener(listener: RealtimePerformanceAlarmListener | null): void {
    this.qualityController.setPerformanceAlarmListener(listener);
  }

  /** @inheritdoc */
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

  /** @inheritdoc */
  async disconnect(): Promise<void> {
    try {
      this.resetStream();
    } finally {
      await this.roomController.leave();
    }
  }

  /** @inheritdoc */
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

  /** @inheritdoc */
  pushLocalVideoFrame(frame: VideoFrame): void {
    this.rtcManager.pushExternalVideoFrame(
      frame,
      this.currentTask?.seiData
    );
  }

  /** @inheritdoc */
  pushLocalAudioFrame(frame: AudioFrame): void {
    if (!this.localAudioPublished) {
      return;
    }

    this.rtcManager.pushExternalAudioFrame(frame);
  }

  /** @inheritdoc */
  beginGeneration(
    taskId: string,
    videoFormat: RealtimeVideoFormat,
    context: RealtimeContext
  ): Promise<void> {
    const confirmation: Promise<void> = this.beginGenerationConfirmation(taskId);
    try {
      this.roomController.startGeneration(taskId, videoFormat, context);
      return confirmation;
    } catch (error) {
      this.stopGeneration(taskId);
      throw XmaxError.from(error);
    }
  }

  /** @inheritdoc */
  updateGeneration(
    taskId: string,
    videoFormat: RealtimeVideoFormat,
    context: RealtimeContext
  ): void {
    this.roomController.changeGenerationCondition(
      taskId,
      videoFormat,
      context
    );
  }

  /** @inheritdoc */
  stopGeneration(taskId: string): void {
    const stoppedTaskId: string = this.stopStreamGeneration(taskId);
    this.roomController.stopGeneration(stoppedTaskId);
  }

  /** @inheritdoc */
  sendTracks(taskId: string, points: RealtimePoint[]): void {
    this.roomController.sendTracks(taskId, points);
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
    if (!published) {
      this.clearRemoteStream();
      return;
    }

    this.rtcManager.subscribeRemoteVideo(userId, true);
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
    if (taskId.length === 0 || message.trim() !== taskId ||
      stream.roomId !== this.roomId ||
      (this.botName.length > 0 && stream.userId !== this.botName)) {
      return;
    }

    if (this.generationStartResolve === null) {
      return;
    }

    try {
      this.remoteStreamListener(stream);
    } catch (error) {
      this.rejectGenerationStart(taskId, XmaxError.from(error));
      return;
    }

    this.resolveGenerationStart(taskId);
  }

  /** 配置当前房间及目标远端用户。 */
  private configureRoom(
    roomId: string,
    botName?: string
  ): void {
    this.roomId = roomId;
    this.botName = botName ?? '';
  }

  /** 发布本地视频，并按需发布本地音频。 */
  private publishLocalStream(includeAudio: boolean): void {
    this.rtcManager.publishLocalVideo();
    if (includeAudio) {
      this.rtcManager.publishLocalAudio();
      this.localAudioPublished = true;
    }
  }

  /** 建立当前生成任务并等待匹配的远端生成流。 */
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

  /** 停止当前生成任务并取消远端生成流等待。 */
  private stopStreamGeneration(
    taskId: string = '',
    reason: string = 'Realtime generation start cancelled'
  ): string {
    const currentTaskId: string = this.currentTask?.id ?? '';
    if (taskId.length > 0 && taskId !== currentTaskId) {
      return '';
    }

    this.clearRemoteStream();
    this.rejectGenerationStart(
      currentTaskId,
      new XmaxError(XmaxErrorCode.CANCELLED, reason)
    );
    this.currentTask = null;
    return currentTaskId;
  }

  /** 清理当前房间内的本地发布和生成流状态。 */
  private resetStream(): void {
    this.stopStreamGeneration();
    this.localAudioPublished = false;
    this.rtcManager.unpublishLocalVideo();
    this.rtcManager.unpublishLocalAudio();
    this.roomId = '';
    this.botName = '';
  }

  /** 通知监听器清除当前远端生成流。 */
  private clearRemoteStream(): void {
    this.remoteStreamListener(null);
  }

  /** 创建远端生成流的限时等待。 */
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

  /** 延迟完成指定生成任务的远端流等待。 */
  private resolveGenerationStart(taskId: string): void {
    if (this.currentTask?.id !== taskId ||
      this.generationStartResolve === null) {
      return;
    }

    const resolve: () => void = this.generationStartResolve;
    this.generationStartResolve = null;

    if (this.generationStartTimer >= 0) {
      clearTimeout(this.generationStartTimer);
    }

    this.generationStartTimer = setTimeout((): void => {
      if (this.currentTask?.id !== taskId ||
        this.generationStartReject === null) {
        return;
      }

      this.clearGenerationStartWaiter();
      resolve();
    }, GENERATION_START_DELAY_MS);
  }

  /** 拒绝指定生成任务的远端流等待。 */
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

  /** 清理远端生成流等待器和超时计时器。 */
  private clearGenerationStartWaiter(): void {
    if (this.generationStartTimer >= 0) {
      clearTimeout(this.generationStartTimer);
      this.generationStartTimer = -1;
    }
    this.generationStartResolve = null;
    this.generationStartReject = null;
  }
}
