//
//  StreamController.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
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
import { RealtimeTiming } from '../service/realtime/RealtimeTiming';
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

/** A server signal confirming generation task startup. */
interface GenerationStartedSignal {

  /** The room signaling event name. */
  event?: string;

  /** The generation task identifier carried by the signal. */
  uid?: string;
}

/**
 * Receives generation result stream creation or clearing notifications.
 *
 * @param stream The generation result stream, or null when the stream is cleared.
 */
type RemoteStreamListener = (
  stream: RemoteStream | null
) => void;

/** An active generation task with consecutive external-frame SEI sequence numbers. */
class GenerationTask {

  // Generation task identity

  /** The generation task identifier. */
  readonly id: string;

  /**
   * Static tasks can confirm through the server start signal so interactions can trigger their
   * first frames.
   */
  readonly staticInput: boolean;

  /** Whether the current task has received server confirmation. */
  confirmed: boolean = false;

  // Video frame SEI sequence

  /** The consecutive video frame index embedded in task SEI. */
  private frameIndex: number = 0;

  /** Creates a generation task context. */
  constructor(
    id: string,
    staticInput: boolean = false
  ) {
    this.id = id;
    this.staticInput = staticInput;
  }

  /**
   * Creates the next task SEI and advances the frame sequence.
   *
   * @returns The UTF-8 task identifier and frame sequence metadata.
   */
  nextSeiData(): Uint8Array {
    const message: string = `${this.id}&index=${this.frameIndex}`;
    this.frameIndex += 1;
    return new util.TextEncoder().encodeInto(message);
  }
}

/** Coordinates RTC rooms, media streams, encoding, and quality. */
export class StreamController implements StreamControlling, RtcEventListener {

  // RTC and stream components

  /** The adapter for RTC engine, room, and media services. */
  private readonly rtcManager: RtcManaging;

  // Stream components

  /** The controller owning RTC room lifecycle and signaling. */
  private readonly roomController: RoomControlling;

  /** The controller applying RTC video encoder settings. */
  private readonly encodingController: EncodingControlling;

  /** The controller for adaptive levels, network metrics, and performance events. */
  private readonly qualityController: QualityControlling;

  // Remote stream and error notifications

  /** The handler for result stream creation and removal. */
  private readonly remoteStreamListener: RemoteStreamListener;

  /** The handler for asynchronous component failures. */
  private readonly errorListener: XmaxErrorListener;

  // Room and generation service user identity

  /** The RTC room identifier. */
  private roomId: string = '';

  /** The generation service user's name. */
  private botName: string = '';

  // Connection and generation timing

  /** The shared connection and generation startup timing recorder. */
  private readonly timing: RealtimeTiming;

  // Local audio publication state

  /** Whether local audio is currently published. */
  private localAudioPublished: boolean = false;

  // Current task and result stream

  /** The pending or confirmed generation task. */
  private currentTask: GenerationTask | null = null;

  /** The remote stream matched to the current generation task. */
  private activeRemoteStream: RemoteStream | null = null;

  // Remote audio playback and subscription state

  /** Whether result audio may be subscribed after first-frame readiness. */
  private remoteAudioActive: boolean = false;

  /** The configured remote audio volume in RTC percentage units. */
  private remoteAudioVolumePercentage: number = DEFAULT_REMOTE_AUDIO_VOLUME;

  /** The users whose remote audio is currently subscribed. */
  private readonly subscribedRemoteAudioUsers: Set<string> = new Set();

  // Result confirmation timeout and completion

  /** The timeout for generation result confirmation. */
  private generationStartTimer: number = -1;

  /** Completes the current task's result confirmation wait. */
  private generationStartResolve: (() => void) | null = null;

  /**
   * Rejects the current task's result confirmation wait.
   *
   * @param reason The error ending generation result confirmation.
   */
  private generationStartReject: ((
    reason: XmaxError
  ) => void) | null = null;

  /**
   * Creates a stream controller and its components.
   *
   * @param rtcManager The manager providing RTC engine services.
   * @param remoteStreamListener The remote video stream change handler.
   * @param errorListener The handler for asynchronous RTC errors without a pending result Promise.
   * @param timing The startup timing recorder shared with the realtime manager.
   * @param historyStore The numeric history store, defaulting to memory.
   */
  constructor(
    rtcManager: RtcManaging,
    remoteStreamListener: RemoteStreamListener,
    errorListener: XmaxErrorListener = (_error: XmaxError): void => { },
    timing: RealtimeTiming = new RealtimeTiming(),
    historyStore: QualityHistoryStore = new MemoryQualityHistoryStore()
  ) {
    this.timing = timing;
    this.rtcManager = rtcManager;

    this.roomController = new RoomController(
      rtcManager,
      timing
    );
    this.encodingController = new EncodingController(rtcManager);
    this.qualityController = new QualityController(
      rtcManager,
      historyStore
    );

    this.remoteStreamListener = remoteStreamListener;
    this.errorListener = errorListener;

    this.rtcManager.setEventListener(this);
  }

  /** The current media baseline and transmission levels, or undefined before preparation. */
  get qualityConfiguration(): QualityConfiguration | undefined {
    return this.qualityController.qualityConfiguration;
  }

  /** Initializes stream quality from the local media baseline and stored history. */
  prepareQuality(
    baseline: RealtimeVideoFormat,
    model: string,
    minimumInputPixels: number = 0,
    isAdaptiveQualityEnabled: boolean = true
  ): QualityConfiguration {
    return this.qualityController.prepareQuality(
      baseline,
      model,
      minimumInputPixels,
      isAdaptiveQualityEnabled
    );
  }

  /** Updates the stream quality baseline while retaining the current levels. */
  rebaseQuality(
    baseline: RealtimeVideoFormat
  ): QualityConfiguration | undefined {
    return this.qualityController.rebaseQuality(baseline);
  }

  /** Sets the adaptive quality recommendation listener. */
  setAdaptiveQualityListener(
    listener: AdaptiveQualityListener | null
  ): void {
    this.qualityController.setAdaptiveQualityListener(listener);
  }

  /** Requests uplink and downlink quality recommendations for a network sample. */
  proposeQuality(
    quality: RealtimeNetworkQuality,
    sampledAt: number
  ): QualityChange {
    return this.qualityController.proposeQuality(
      quality,
      sampledAt
    );
  }

  /** Records whether a quality change was successfully submitted. */
  completeQuality(
    downlink: boolean,
    level: number,
    success: boolean
  ): void {
    this.qualityController.completeQuality(
      downlink,
      level,
      success
    );
  }

  /** Clears consecutive samples while retaining quality levels. */
  resetQualitySamples(): void {
    this.qualityController.resetQualitySamples();
  }

  /**
   * Submits task result dimensions and bitrate without waiting for server application.
   *
   * @param taskId The current generation task identifier.
   * @param targetSize The optional result stream target dimensions.
   */
  changeTargetSize(
    taskId: string,
    targetSize: ImageSize
  ): void {
    if (taskId.length === 0 || this.currentTask?.id !== taskId) {
      throw new XmaxError(
        XmaxErrorCode.CANCELLED,
        'Generation task is no longer active'
      );
    }
    this.roomController.changeTargetSize(
      taskId,
      targetSize
    );
  }

  /** The active generation task identifier, or an empty string before generation. */
  get currentGenerationTaskId(): string {
    return this.currentTask?.id ?? '';
  }

  /** The generation result playback volume in 0 to 1; zero mutes and one uses original volume. */
  get remoteAudioVolume(): number {
    return this.remoteAudioVolumePercentage / 100;
  }

  /**
   * Sets remote volume in 0 to 1, caching it before subscription.
   *
   * @param volume The volume in 0 to 1, from muted to original volume.
   */
  setRemoteAudioVolume(
    volume: number
  ): void {
    const rtcVolume: number = Math.round(volume * 100);
    this.subscribedRemoteAudioUsers.forEach((userId: string): void => {
      this.rtcManager.setRemoteAudioVolume(
        userId,
        rtcVolume
      );
    });
    this.remoteAudioVolumePercentage = rtcVolume;
  }

  /**
   * Configures the realtime video encoder.
   *
   * @param videoFormat The RTC encoding width, height, and frame rate.
   */
  setVideoEncoderConfig(
    videoFormat: RealtimeVideoFormat
  ): void {
    this.encodingController.configure(videoFormat);
  }

  /** Sets the uplink video statistics listener; null removes it. */
  setUplinkVideoStatisticsListener(
    listener: UplinkVideoStatisticsListener | null
  ): void {
    this.qualityController.setUplinkVideoStatisticsListener(listener);
  }

  /** Sets the result stream video statistics listener; null removes it. */
  setDownlinkVideoStatisticsListener(
    listener: DownlinkVideoStatisticsListener | null
  ): void {
    this.qualityController.setDownlinkVideoStatisticsListener(listener);
  }

  /** Sets the realtime network quality listener. */
  setNetworkQualityListener(
    listener: RealtimeNetworkQualityListener | null
  ): void {
    this.qualityController.setNetworkQualityListener(listener);
  }

  /** Sets the device performance alarm listener. */
  setPerformanceAlarmListener(
    listener: RealtimePerformanceAlarmListener | null
  ): void {
    this.qualityController.setPerformanceAlarmListener(listener);
  }

  /**
   * Joins the RTC room and publishes local media.
   *
   * @param connection The room, user, token, and target bot information.
   * @param includeLocalAudio Whether to publish local audio with video.
   * @param ensureActive The callback checking connection validity across asynchronous boundaries.
   */
  async connect(
    connection: RealtimeSessionConnection,
    includeLocalAudio: boolean,
    ensureActive: () => void
  ): Promise<void> {
    await this.roomController.join(
      connection,
      ensureActive
    );
    ensureActive();

    this.configureRoom(
      connection.roomId,
      connection.botName
    );

    this.publishLocalStream(includeLocalAudio);
  }

  /** Clears stream state and leaves the room, returning safely without an active room. */
  async disconnect(): Promise<void> {
    try {
      this.resetStream();
    } finally {
      await this.roomController.leave();
    }
  }

  /**
   * Updates local audio publication.
   *
   * @param enabled Whether to publish local audio.
   */
  setLocalAudioEnabled(
    enabled: boolean
  ): void {
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
   * Submits a local external video frame.
   *
   * @param frame The local video frame ready for RTC.
   */
  pushLocalVideoFrame(
    frame: VideoFrame
  ): void {
    const task: GenerationTask | null = this.currentTask;
    this.rtcManager.pushExternalVideoFrame(
      frame,
      task?.nextSeiData()
    );
  }

  /**
   * Submits a local external audio frame.
   *
   * @param frame The local PCM frame ready for RTC.
   */
  pushLocalAudioFrame(
    frame: AudioFrame
  ): void {
    if (!this.localAudioPublished) {
      return;
    }

    this.rtcManager.pushExternalAudioFrame(frame);
  }

  /**
   * Creates a generation task, sends its start signal, and waits for a matching result stream.
   *
   * @param taskId The current generation task identifier.
   * @param videoFormat The current local media format.
   * @param context The generation task's conditions.
   * @param faceRestoration Whether to enable face restoration.
   * @param targetSize The optional result stream target dimensions.
   * @param paddingContain Whether to preserve media aspect ratio with server-side padding.
   * @param extraParams The static generation parameters passed internally by the SDK.
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
    const confirmation: Promise<void> = this.beginGenerationConfirmation(
      taskId,
      extraParams?.static_generate === true
    );

    try {
      this.roomController.startGeneration(
        taskId,
        videoFormat,
        context,
        faceRestoration,
        targetSize,
        paddingContain,
        extraParams
      );
      this.timing.finishSignal(taskId);
      return confirmation;
    } catch (error) {
      // Reject only the existing result Promise; a second throw could leave cancellation unhandled.
      this.rejectGenerationStart(
        taskId,
        XmaxError.from(error)
      );
      return confirmation;
    }
  }

  /** Activates matched result audio after first-frame readiness. */
  activateRemoteAudio(): void {
    const stream: RemoteStream | null = this.activeRemoteStream;
    if (this.currentTask?.staticInput && stream === null) {
      // A static task is confirmed before SEI video arrives; activate audio after result stream matching.
      this.remoteAudioActive = true;
      return;
    }
    if (this.currentTask === null || stream === null) {
      throw new XmaxError(
        XmaxErrorCode.RTC_ERROR,
        'Remote generation audio stream is unavailable'
      );
    }

    this.subscribeRemoteAudio(stream.userId);
    this.remoteAudioActive = true;
  }

  /**
   * Sends updated generation conditions.
   *
   * @param taskId The current generation task identifier.
   * @param videoFormat The current local media format.
   * @param context The updated generation conditions.
   * @param faceRestoration Whether to enable face restoration.
   * @param targetSize The optional result stream target dimensions.
   * @param paddingContain Whether to preserve media aspect ratio with server-side padding.
   * @param extraParams The static generation parameters passed internally by the SDK.
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
   * Stops a generation task and clears its result stream.
   *
   * @param taskId The task to stop; an empty string selects the current task.
   */
  stopGeneration(
    taskId: string
  ): void {
    const stoppedTaskId: string = this.stopStreamGeneration(taskId);
    this.roomController.stopGeneration(stoppedTaskId);
  }

  /** Sends normalized interaction points for the generation task. */
  sendTracks(
    taskId: string,
    points: RealtimePoint[]
  ): void {
    this.roomController.sendTracks(
      taskId,
      points
    );
  }

  /**
   * Subscribes to generation audio for internal RTC playback.
   *
   * @param userId The remote user identifier.
   * @param published Whether remote audio is published.
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
        XmaxLogger.error(
          `${XmaxLogger.localized("清理远端流失败 (Remote Stream Cleanup Failed)\n└─ 原因：", "清理远端流失败 (Remote Stream Cleanup Failed)\n└─ Reason: ")}${XmaxError.from(error).message}`,
          'Stream'
        );
      }
    }
  }

  /**
   * Handles remote video publication changes.
   *
   * @param userId The remote user identifier.
   * @param published Whether remote video is published.
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

      this.rtcManager.subscribeRemoteVideo(
        userId,
        true
      );
    } catch (error) {
      if (published) {
        this.handleRtcEventError(XmaxError.from(error));
      } else {
        XmaxLogger.error(
          `${XmaxLogger.localized("清理远端流失败 (Remote Stream Cleanup Failed)\n└─ 原因：", "清理远端流失败 (Remote Stream Cleanup Failed)\n└─ Reason: ")}${XmaxError.from(error).message}`,
          'Stream'
        );
      }
    }
  }

  /**
   * Static interaction need not await video; accept start confirmation only for the current server
   * and task.
   */
  onRoomSignalReceived(
    userId: string,
    message: string
  ): void {
    const task: GenerationTask | null = this.currentTask;
    if (task === null || !task.staticInput || this.generationStartResolve === null ||
      this.botName.length === 0 || userId !== this.botName) {
      return;
    }

    let signal: GenerationStartedSignal;
    try {
      signal = JSON.parse(message) as GenerationStartedSignal;
    } catch (_error) {
      return;
    }
    if (signal === null || signal.event !== 'video_started' ||
      typeof signal.uid !== 'string' || !this.matchesTaskSei(
        signal.uid,
        task.id
      )) {
      return;
    }

    this.timing.matchSEI(task.id);
    XmaxLogger.debug(
      'Static generation confirmed by video_started: ' + task.id,
      'Stream'
    );
    this.resolveGenerationStart(task.id);
  }

  /**
   * Matches remote generation streams by SEI task identity.
   *
   * @param stream The remote stream carrying SEI.
   * @param message The received SEI text.
   */
  onSeiMessageReceived(
    stream: RemoteStream,
    message: string
  ): void {
    const taskId: string = this.currentTask?.id ?? '';
    if (taskId.length === 0 || !this.matchesTaskSei(
      message,
      taskId
    ) ||
      stream.roomId !== this.roomId ||
      (this.botName.length > 0 && stream.userId !== this.botName)) {
      return;
    }

    if (this.activeRemoteStream !== null ||
      (this.generationStartResolve === null && this.currentTask?.confirmed !== true)) {
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
      if (this.remoteAudioActive) {
        this.subscribeRemoteAudio(stream.userId);
      }
    } catch (error) {
      this.handleRtcEventError(XmaxError.from(error));
      return;
    }

    this.resolveGenerationStart(taskId);
  }

  /**
   * Matches the task identifier before query parameters; os and index are not part of task
   * identity.
   *
   * @param message The received task identifier and optional query parameters.
   * @param taskId The current generation task identifier.
   *
   * @returns True if the SEI task identifier matches the task.
   */
  private matchesTaskSei(
    message: string,
    taskId: string
  ): boolean {
    const receivedId: string = message.trim().split('?')[0];
    const currentId: string = taskId.split('?')[0];
    return receivedId.length > 0 && receivedId === currentId;
  }

  /**
   * Report startup subscription failures through the pending Promise; other asynchronous failures
   * use the listener.
   *
   * @param error The asynchronous RTC failure to deliver through the pending wait or error
   * listener.
   */
  private handleRtcEventError(
    error: XmaxError
  ): void {
    const taskId: string = this.currentTask?.id ?? '';
    if (taskId.length > 0 &&
      this.generationStartReject !== null) {
      this.rejectGenerationStart(
        taskId,
        error
      );
      return;
    }

    this.errorListener(error);
  }

  /**
   * Subscribes to a remote user's audio and records subscription state.
   *
   * @param userId The RTC user identifier.
   */
  private subscribeRemoteAudio(
    userId: string
  ): void {
    if (this.subscribedRemoteAudioUsers.has(userId)) {
      return;
    }

    this.rtcManager.setRemoteAudioVolume(
      userId,
      this.remoteAudioVolumePercentage
    );
    this.rtcManager.subscribeRemoteAudio(
      userId,
      true
    );
    this.subscribedRemoteAudioUsers.add(userId);
  }

  /**
   * Unsubscribes remote audio and clears its subscription record.
   *
   * @param userId The RTC user identifier.
   */
  private unsubscribeRemoteAudio(
    userId: string
  ): void {
    if (!this.subscribedRemoteAudioUsers.delete(userId)) {
      return;
    }

    try {
      this.rtcManager.subscribeRemoteAudio(
        userId,
        false
      );
    } catch (error) {
      XmaxLogger.error(
        `${XmaxLogger.localized("取消远端音频订阅失败 (Failed to Unsubscribe Remote Audio)\n└─ 原因：", "取消远端音频订阅失败 (Failed to Unsubscribe Remote Audio)\n└─ Reason: ")}${XmaxError.from(error).message}`,
        'Stream'
      );
    }
  }

  /**
   * Configures the current room and target remote user.
   *
   * @param roomId The RTC room identifier.
   * @param botName The generation service user name.
   */
  private configureRoom(
    roomId: string,
    botName?: string
  ): void {
    this.roomId = roomId;
    this.botName = botName ?? '';
  }

  /**
   * Publishes local video and optional local audio.
   *
   * @param includeAudio Whether to publish local audio.
   */
  private publishLocalStream(
    includeAudio: boolean
  ): void {
    this.rtcManager.publishLocalVideo();
    this.qualityController.setUplinkVideoStatisticsEnabled(true);

    if (includeAudio) {
      this.rtcManager.publishLocalAudio();
      this.localAudioPublished = true;
    }
  }

  /**
   * Creates the active task and waits for its matching result stream.
   *
   * @param taskId The current generation task identifier.
   */
  private beginGenerationConfirmation(
    taskId: string,
    staticInput: boolean = false
  ): Promise<void> {
    if (this.currentTask !== null) {
      throw new XmaxError(
        XmaxErrorCode.RTC_ERROR,
        'Realtime generation is already active'
      );
    }

    this.currentTask = new GenerationTask(
      taskId,
      staticInput
    );
    return this.waitForGenerationStart(taskId);
  }

  /**
   * Stops the active task and cancels its result wait.
   *
   * @param taskId The current generation task identifier.
   * @param reason The termination reason or platform alarm reason.
   *
   * @returns The stopped task identifier, or an empty string for a mismatch or absent task.
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
      new XmaxError(
        XmaxErrorCode.CANCELLED,
        reason
      )
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

  /** Clears local publication and generation state for the room. */
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

  /** Notifies listeners to clear the current result stream. */
  private clearRemoteStream(): void {
    this.qualityController.setDownlinkVideoStatisticsUser(undefined);
    this.remoteStreamListener(null);
  }

  /**
   * Creates a timed result stream wait.
   *
   * @param taskId The current generation task identifier.
   */
  private waitForGenerationStart(
    taskId: string
  ): Promise<void> {
    this.clearGenerationStartWaiter();

    return new Promise((resolve: () => void, reject: (
      reason: XmaxError
    ) => void) => {
      this.generationStartResolve = resolve;
      this.generationStartReject = reject;
      this.generationStartTimer = setTimeout(
        (): void => {
          this.rejectGenerationStart(
            taskId,
            new XmaxError(
              XmaxErrorCode.TIMEOUT,
              'Realtime generation start timed out'
            )
          );
        },
        GENERATION_START_TIMEOUT_MS
      );
    });
  }

  /**
   * SEI matching completes stream confirmation immediately; Core then waits for a usable first
   * frame.
   *
   * @param taskId The current generation task identifier.
   */
  private resolveGenerationStart(
    taskId: string
  ): void {
    if (this.currentTask?.id !== taskId ||
      this.generationStartResolve === null) {
      return;
    }

    const resolve: () => void = this.generationStartResolve;
    this.currentTask.confirmed = true;
    this.clearGenerationStartWaiter();
    resolve();
  }

  /**
   * Rejects a task's result stream wait.
   *
   * @param taskId The current generation task identifier.
   * @param error The failure rejecting confirmation for the matching generation task.
   */
  private rejectGenerationStart(
    taskId: string,
    error: XmaxError
  ): void {
    if (taskId.length === 0 || this.currentTask?.id !== taskId ||
      this.generationStartReject === null) {
      return;
    }

    const reject: (
      reason: XmaxError
    ) => void = this.generationStartReject;
    this.clearGenerationStartWaiter();
    reject(error);
  }

  /** Clears result waiters and their timeout. */
  private clearGenerationStartWaiter(): void {
    if (this.generationStartTimer >= 0) {
      clearTimeout(this.generationStartTimer);
      this.generationStartTimer = -1;
    }

    this.generationStartResolve = null;
    this.generationStartReject = null;
  }
}
