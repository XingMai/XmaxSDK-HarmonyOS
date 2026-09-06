import { XmaxError, XmaxErrorCode, XmaxErrorListener, XmaxErrorSeverity } from '../foundation/errors/XmaxError';
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

const REMOTE_FRAME_TIMEOUT_MS: number = 10000;

class RemoteFrameWaiter {
  timer: number = -1;
  readonly resolve: () => void;
  readonly reject: (error: XmaxError) => void;

  constructor(resolve: () => void, reject: (error: XmaxError) => void) {
    this.resolve = resolve;
    this.reject = reject;
  }
}

/** 统一协调视频轨道、RTC 画面和轨迹交互的渲染资源。 */
export class RenderController implements RenderControlling {

  // 基础层组件
  private readonly rtcManager: RtcManaging;
  private readonly errorListener: XmaxErrorListener;
  private remoteBinding: VideoRenderBinding | null = null;
  private remoteStream: RemoteStream | null = null;
  private remoteFrameReady: boolean = false;
  private remoteFrameError: XmaxError | null = null;
  private readonly remoteFrameWaiters: Set<RemoteFrameWaiter> = new Set();

  // 渲染层组件
  private readonly remoteVideoController: RemoteVideoControlling;

  /**
   * 创建渲染层统一 Controller 并完成内部组件装配。
   *
   * @param rtcManager 提供远端视频绑定能力的 RTC Manager。
   * @param errorListener 接收渲染视图异步绑定失败。
   */
  constructor(
    rtcManager: RtcManaging,
    errorListener: XmaxErrorListener = (_error: XmaxError): void => {}
  ) {
    this.rtcManager = rtcManager;
    this.errorListener = errorListener;
    this.remoteVideoController = new RemoteVideoController(rtcManager, (ready: boolean): void => {
      this.remoteBinding?.setVideoReady(ready);
    });
    rtcManager.setRemoteVideoFrameListener((stream: RemoteStream): void => {
      if (this.remoteStream?.key() !== stream.key() || this.remoteFrameError !== null ||
        this.remoteFrameReady) {
        return;
      }
      this.remoteFrameReady = true;
      this.stopFrameObservation(stream);
      this.finishRemoteFrameWaiters();
    });
  }

  /** @inheritdoc */
  setRemoteStream(stream: RemoteStream | null): void {
    this.resetRemoteFrameWait();
    this.remoteStream = stream;
    this.remoteVideoController.setRemoteStream(stream);
    if (stream !== null) {
      this.rtcManager.observeRemoteVideoFrames(stream, true);
    }
  }

  /** @inheritdoc */
  waitUntilRemoteFrameReady(): Promise<void> {
    if (this.remoteStream === null) {
      return Promise.reject(new XmaxError(XmaxErrorCode.CANCELLED,
        'Remote video first frame wait was cancelled'));
    }
    if (this.remoteFrameError !== null) {
      return Promise.reject(this.remoteFrameError);
    }
    if (this.remoteFrameReady) {
      return Promise.resolve();
    }
    return new Promise<void>((resolve: () => void, reject: (error: XmaxError) => void): void => {
      const waiter = new RemoteFrameWaiter(resolve, reject);
      this.remoteFrameWaiters.add(waiter);
      waiter.timer = setTimeout((): void => {
        if (this.remoteFrameWaiters.has(waiter)) {
          this.failRemoteFrameWait(new XmaxError(XmaxErrorCode.TIMEOUT,
            'Remote video first frame timed out'));
        }
      }, REMOTE_FRAME_TIMEOUT_MS);
    });
  }

  /** @inheritdoc */
  failRemoteFrameWait(error: XmaxError): void {
    if (this.remoteStream === null || this.remoteFrameReady || this.remoteFrameError !== null) {
      return;
    }
    this.remoteFrameError = error;
    this.stopFrameObservation(this.remoteStream);
    this.finishRemoteFrameWaiters(error);
  }

  private resetRemoteFrameWait(): void {
    const stream: RemoteStream | null = this.remoteStream;
    this.remoteStream = null;
    this.remoteFrameReady = false;
    this.remoteFrameError = null;
    this.finishRemoteFrameWaiters(new XmaxError(XmaxErrorCode.CANCELLED,
      'Remote video first frame wait was cancelled'));
    if (stream !== null) {
      this.stopFrameObservation(stream);
    }
  }

  private finishRemoteFrameWaiters(error?: XmaxError): void {
    this.remoteFrameWaiters.forEach((waiter: RemoteFrameWaiter): void => {
      clearTimeout(waiter.timer);
      if (error === undefined) {
        waiter.resolve();
      } else {
        waiter.reject(error);
      }
    });
    this.remoteFrameWaiters.clear();
  }

  private stopFrameObservation(stream: RemoteStream): void {
    try {
      this.rtcManager.observeRemoteVideoFrames(stream, false);
    } catch (error) {
      this.errorListener(XmaxError.from(error).withSeverity(XmaxErrorSeverity.RECOVERABLE));
    }
  }

  /** @inheritdoc */
  registerRemoteTrack(
    track: RealtimeVideoTrack,
    interactionController: InteractionControlling
  ): void {
    const binding = new VideoRenderBinding(
      this.rtcManager.renderLibraryName(),
      (
        viewId: string,
        contentMode: VideoContentMode
      ): void => {
        try {
          this.remoteVideoController.attach(viewId, contentMode);
        } catch (error) {
          binding.setVideoReady(false);
          this.errorListener(XmaxError.from(error));
        }
      },
      (viewId: string): void => {
        this.remoteVideoController.detach(viewId);
      }
    );
    this.remoteBinding = binding;
    VideoRenderRegistry.register(track, binding);
    TrajectoryRegistry.register(
      track,
      new TrajectoryBinding(interactionController)
    );
  }

  /** @inheritdoc */
  resetRemoteTrack(track: RealtimeVideoTrack | null): void {
    this.resetRemoteFrameWait();
    if (track !== null) {
      VideoRenderRegistry.unregister(track);
      TrajectoryRegistry.unregister(track);
    }
    this.remoteVideoController.reset();
    this.remoteBinding = null;
  }
}
