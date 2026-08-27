import { RemoteStream } from '../foundation/rtc/RemoteStream';
import { RtcManaging } from '../foundation/rtc/RtcManaging';
import { VideoContentMode } from '../foundation/media/video/VideoContentMode';
import { InteractionControlling } from '../media/interaction/InteractionControlling';
import { RealtimeVideoTrack } from '../service/realtime/RealtimeVideoTrack';
import { RenderControlling } from './RenderControlling';
import { TrajectoryBinding } from './trajectory/TrajectoryBinding';
import { TrajectoryRegistry } from './trajectory/TrajectoryRegistry';
import { RemoteVideoController } from './video/RemoteVideoController';
import { RemoteVideoControlling } from './video/RemoteVideoControlling';
import {
  VideoRenderBinding,
  VideoRenderRegistry
} from './video/VideoRenderRegistry';

/** 统一协调视频轨道、RTC 画面和轨迹交互的渲染资源。 */
export class RenderController implements RenderControlling {

  // 基础层组件
  private readonly rtcManager: RtcManaging;

  // 渲染层组件
  private readonly remoteVideoController: RemoteVideoControlling;

  /**
   * 创建渲染层统一 Controller 并完成内部组件装配。
   *
   * @param rtcManager 提供远端视频绑定能力的 RTC Manager。
   */
  constructor(rtcManager: RtcManaging) {
    this.rtcManager = rtcManager;
    this.remoteVideoController = new RemoteVideoController(rtcManager);
  }

  /** @inheritdoc */
  setRemoteStream(stream: RemoteStream | null): void {
    this.remoteVideoController.setRemoteStream(stream);
  }

  /** @inheritdoc */
  registerRemoteTrack(
    track: RealtimeVideoTrack,
    interactionController: InteractionControlling
  ): void {
    VideoRenderRegistry.register(track, new VideoRenderBinding(
      this.rtcManager.renderLibraryName(),
      (
        viewId: string,
        contentMode: VideoContentMode
      ): void => {
        this.remoteVideoController.attach(viewId, contentMode);
      },
      (viewId: string): void => {
        this.remoteVideoController.detach(viewId);
      }
    ));
    TrajectoryRegistry.register(
      track,
      new TrajectoryBinding(interactionController)
    );
  }

  /** @inheritdoc */
  resetRemoteTrack(track: RealtimeVideoTrack | null): void {
    if (track !== null) {
      VideoRenderRegistry.unregister(track);
      TrajectoryRegistry.unregister(track);
    }
    this.remoteVideoController.reset();
  }
}
