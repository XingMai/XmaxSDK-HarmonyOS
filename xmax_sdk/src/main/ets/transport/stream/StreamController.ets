import { util } from '@kit.ArkTS';
import { AudioFrame } from '../../foundation/media/audio/AudioFrame';
import {
  XmaxError,
  XmaxErrorCode
} from '../../foundation/errors/XmaxError';
import { RemoteStream } from '../../foundation/rtc/RemoteStream';
import { RtcManaging } from '../../foundation/rtc/RtcManaging';
import { RtcEventListener } from '../../foundation/rtc/RtcEventListener';
import { VideoFrame } from '../../foundation/media/video/VideoFrame';
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

/** 管理本地媒体发布、外部帧推送和远端生成流匹配。 */
export class StreamController implements StreamControlling, RtcEventListener {

  // 基础层组件
  private readonly rtcManager: RtcManaging;

  // 远端流监听器
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
   * 创建媒体流 Controller。
   *
   * @param rtcManager 提供媒体流传输能力的 RTC Manager。
   * @param remoteStreamListener 远端生成流变更监听器。
   */
  constructor(
    rtcManager: RtcManaging,
    remoteStreamListener: RemoteStreamListener
  ) {
    // 基础层组件
    this.rtcManager = rtcManager;

    // 远端流监听器
    this.remoteStreamListener = remoteStreamListener;

    this.rtcManager.setEventListener(this);
  }

  /**
   * 配置当前房间及目标远端用户。
   *
   * @param roomId 房间标识。
   * @param botName 目标远端用户名称。
   * @returns 无返回值。
   */
  configureRoom(
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
  publishLocalStream(includeAudio: boolean): void {
    this.rtcManager.publishLocalVideo();
    if (includeAudio) {
      this.rtcManager.publishLocalAudio();
      this.localAudioPublished = true;
    }
  }

  /**
   * 更新本地音频的发布状态。
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
   * 推送本地外部视频帧，并附带当前任务的 SEI 数据。
   *
   * @param frame 本地视频帧。
   * @returns 无返回值。
   */
  pushLocalVideoFrame(frame: VideoFrame): void {
    this.rtcManager.pushExternalVideoFrame(
      frame,
      this.currentTask?.seiData
    );
  }

  /**
   * 在本地音频已发布时推送外部音频帧。
   *
   * @param frame 本地音频帧。
   * @returns 无返回值。
   */
  pushLocalAudioFrame(frame: AudioFrame): void {
    if (!this.localAudioPublished) {
      return;
    }

    this.rtcManager.pushExternalAudioFrame(frame);
  }

  /**
   * 建立当前生成任务并等待匹配的远端生成流。
   *
   * @param taskId 生成任务标识。
   * @returns 匹配到远端生成流后的 Promise。
   */
  beginGeneration(taskId: string): Promise<void> {
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
   * @param taskId 生成任务标识；传入空字符串时停止当前任务。
   * @param reason 取消等待时使用的错误原因。
   * @returns 实际停止的任务标识；没有匹配任务时返回空字符串。
   */
  stopGeneration(
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

  /**
   * 清理当前房间内的本地发布和生成流状态。
   *
   * @returns 无返回值。
   */
  resetRoom(): void {
    this.stopGeneration();
    this.localAudioPublished = false;
    this.rtcManager.unpublishLocalVideo();
    this.rtcManager.unpublishLocalAudio();
    this.roomId = '';
    this.botName = '';
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

  /**
   * 通知监听器清除当前远端生成流。
   *
   * @returns 无返回值。
   */
  private clearRemoteStream(): void {
    this.remoteStreamListener(null);
  }

  /**
   * 创建远端生成流的限时等待。
   *
   * @param taskId 生成任务标识。
   * @returns 匹配到远端生成流后的 Promise。
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
   * 延迟完成指定生成任务的远端流等待。
   *
   * @param taskId 生成任务标识。
   * @returns 无返回值。
   */
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

  /**
   * 拒绝指定生成任务的远端流等待。
   *
   * @param taskId 生成任务标识。
   * @param error 拒绝等待时返回的错误。
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
