import { AudioFrame } from '../foundation/media/audio/AudioFrame';
import { VideoFrame } from '../foundation/media/video/VideoFrame';
import { XmaxError } from '../foundation/errors/XmaxError';
import { RemoteStream } from '../foundation/rtc/RemoteStream';
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
import { StreamController } from './stream/StreamController';
import { StreamControlling } from './stream/StreamControlling';
import { TransportControlling } from './TransportControlling';

/** 统一协调 RTC 房间、媒体流、编码和质量事件。 */
export class TransportController implements TransportControlling {

  // 传输层组件
  private readonly roomController: RoomControlling;
  private readonly streamController: StreamControlling;
  private readonly encodingController: EncodingControlling;
  private readonly qualityController: QualityControlling;

  /**
   * 创建传输层统一 Controller 并完成内部组件装配。
   *
   * @param rtcManager 提供 RTC 引擎基础能力的 Manager。
   * @param remoteStreamListener 接收远端视频流变化的监听器。
   */
  constructor(
    rtcManager: RtcManaging,
    remoteStreamListener: (stream: RemoteStream | null) => void
  ) {
    this.roomController = new RoomController(rtcManager);
    this.streamController = new StreamController(rtcManager, remoteStreamListener);
    this.encodingController = new EncodingController(rtcManager);
    this.qualityController = new QualityController(rtcManager);
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
    this.streamController.configureRoom(connection.roomId, connection.botName);
    this.streamController.publishLocalStream(includeLocalAudio);
  }

  /** @inheritdoc */
  async disconnect(): Promise<void> {
    try {
      this.streamController.resetRoom();
    } finally {
      await this.roomController.leave();
    }
  }

  /** @inheritdoc */
  setLocalAudioEnabled(enabled: boolean): void {
    this.streamController.setLocalAudioEnabled(enabled);
  }

  /** @inheritdoc */
  pushLocalVideoFrame(frame: VideoFrame): void {
    this.streamController.pushLocalVideoFrame(frame);
  }

  /** @inheritdoc */
  pushLocalAudioFrame(frame: AudioFrame): void {
    this.streamController.pushLocalAudioFrame(frame);
  }

  /** @inheritdoc */
  beginGeneration(
    taskId: string,
    videoFormat: RealtimeVideoFormat,
    context: RealtimeContext
  ): Promise<void> {
    const confirmation: Promise<void> = this.streamController.beginGeneration(taskId);
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
    const stoppedTaskId: string = this.streamController.stopGeneration(taskId);
    this.roomController.stopGeneration(stoppedTaskId);
  }

  /** @inheritdoc */
  sendTracks(taskId: string, points: RealtimePoint[]): void {
    this.roomController.sendTracks(taskId, points);
  }
}
