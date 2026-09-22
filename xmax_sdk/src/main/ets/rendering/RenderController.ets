import { RealtimeVideoFrame, RealtimeVideoFrameListener } from '../service/realtime/RealtimeVideoFrame';
import { image } from '@kit.ImageKit';
import { RealtimeVideoFrameDispatcher } from './video/RealtimeVideoFrameDispatcher';
import { XmaxLogger } from '../foundation/logging/XmaxLogger';
import { XmaxError, XmaxErrorCode, XmaxErrorListener } from '../foundation/errors/XmaxError';
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
const REMOTE_NEXT_FRAME_TIMEOUT_MS: number = 1500;

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
  private remoteFrameDeliveryActive: boolean = false;
  private readonly frameDispatcher: RealtimeVideoFrameDispatcher = new RealtimeVideoFrameDispatcher();
  private remoteFrameError: XmaxError | null = null;
  private readonly remoteFrameWaiters: Set<RemoteFrameWaiter> = new Set();
  private nextRemoteFrameWaiter: RemoteFrameWaiter | null = null;
  private frozenRemoteFrame: image.PixelMap | null = null;
  private remoteFreezeVersion: number = 0;

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
    rtcManager.setRemoteVideoFrameListener((stream: RemoteStream, copyFrame: () => RealtimeVideoFrame): void => {
      if (this.remoteStream?.key() !== stream.key() || this.remoteFrameError !== null) {
        return;
      }
      if (!this.remoteFrameReady) {
        this.remoteFrameReady = true;
        this.finishRemoteFrameWaiters();
      }
      // 恢复播放只需要下一帧到达的通知；只有公开帧监听器需要复制像素。
      this.finishNextRemoteFrameWait();
      const shouldDeliver: boolean = this.frameDispatcher.hasListener && this.remoteFrameDeliveryActive;
      if (!shouldDeliver) {
        this.stopFrameObservation(stream);
        return;
      }
      try {
        const frame: RealtimeVideoFrame = copyFrame();
        this.frameDispatcher.dispatch(frame);
      } catch (error) {
        XmaxLogger.error(`${XmaxLogger.localized("复制远端视频帧失败 (Remote Video Frame Copy Failed)\n└─ 原因：", "复制远端视频帧失败 (Remote Video Frame Copy Failed)\n└─ Reason: ")}${XmaxError.from(error).message}`, 'Render');
      }
    });
  }

  /** @inheritdoc */
  setRemoteVideoFrameListener(listener: RealtimeVideoFrameListener | null): void {
    const stream: RemoteStream | null = this.remoteStream;
    // 先开启观察，失败时保留原监听器和已排队的帧。
    if (listener !== null && stream !== null && this.remoteFrameDeliveryActive && this.remoteFrameError === null) {
      this.rtcManager.observeRemoteVideoFrames(stream, true);
    }
    this.frameDispatcher.setListener(listener);
    if (listener === null && stream !== null && this.remoteFrameReady && this.nextRemoteFrameWaiter === null) {
      this.stopFrameObservation(stream);
    }
  }

  /** @inheritdoc */
  stopRemoteVideoFrameDelivery(): void {
    this.remoteFrameDeliveryActive = false;
    this.frameDispatcher.invalidatePendingFrames();
  }

  /** @inheritdoc */
  async freezeRemoteVideo(): Promise<void> {
    const version: number = ++this.remoteFreezeVersion;
    const stream: RemoteStream | null = this.remoteStream;
    const binding: VideoRenderBinding | null = this.remoteBinding;
    if (stream === null || binding === null) {
      return;
    }
    try {
      const pixelMap: image.PixelMap = await this.rtcManager.takeRemoteSnapshot(stream);
      if (version !== this.remoteFreezeVersion ||
        this.remoteStream?.key() !== stream.key() || this.remoteBinding !== binding) {
        await pixelMap.release();
        return;
      }
      await this.clearFrozenRemoteFrame();
      if (version !== this.remoteFreezeVersion) {
        await pixelMap.release();
        return;
      }
      this.frozenRemoteFrame = pixelMap;
      binding.setPreviewFrame(pixelMap);
    } catch (error) {
      XmaxLogger.error(
        `${XmaxLogger.localized("冻结远端视频画面失败 (Failed to Freeze Remote Video)\n└─ 原因：", "冻结远端视频画面失败 (Failed to Freeze Remote Video)\n└─ Reason: ")}${XmaxError.from(error).message}`,
        'Render'
      );
    }
  }

  /** @inheritdoc */
  async resumeRemoteVideo(): Promise<void> {
    const version: number = ++this.remoteFreezeVersion;
    if (this.frozenRemoteFrame === null) {
      return;
    }
    try {
      if (this.remoteStream !== null) {
        await this.waitForNextRemoteFrame();
      }
    } catch (error) {
      XmaxLogger.error(
        `${XmaxLogger.localized("等待远端视频恢复帧失败 (Failed to Wait for Remote Video Resume Frame)\n└─ 原因：", "等待远端视频恢复帧失败 (Failed to Wait for Remote Video Resume Frame)\n└─ Reason: ")}${XmaxError.from(error).message}`,
        'Render'
      );
    }
    if (version === this.remoteFreezeVersion) {
      await this.clearFrozenRemoteFrame();
    }
  }

  /** @inheritdoc */
  setRemoteStream(stream: RemoteStream | null): void {
    this.resetRemoteFrameWait();
    this.remoteStream = stream;
    this.remoteFrameDeliveryActive = stream !== null;
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
    this.stopRemoteVideoFrameDelivery();
    this.remoteFrameError = error;
    this.stopFrameObservation(this.remoteStream);
    this.finishRemoteFrameWaiters(error);
    this.finishNextRemoteFrameWait(error);
  }

  private resetRemoteFrameWait(): void {
    ++this.remoteFreezeVersion;
    this.stopRemoteVideoFrameDelivery();
    const stream: RemoteStream | null = this.remoteStream;
    this.remoteStream = null;
    this.remoteFrameReady = false;
    this.remoteFrameError = null;
    this.finishNextRemoteFrameWait(new XmaxError(
      XmaxErrorCode.CANCELLED,
      'Remote video next frame wait was cancelled'
    ));
    void this.clearFrozenRemoteFrame();
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

  private waitForNextRemoteFrame(): Promise<void> {
    const stream: RemoteStream | null = this.remoteStream;
    if (stream === null || this.remoteFrameError !== null) {
      return Promise.reject(this.remoteFrameError ?? new XmaxError(
        XmaxErrorCode.CANCELLED,
        'Remote video next frame wait is unavailable'
      ));
    }
    this.finishNextRemoteFrameWait(new XmaxError(
      XmaxErrorCode.CANCELLED,
      'Remote video next frame wait was replaced'
    ));
    return new Promise<void>((
      resolve: () => void,
      reject: (error: XmaxError) => void
    ): void => {
      const waiter = new RemoteFrameWaiter(resolve, reject);
      this.nextRemoteFrameWaiter = waiter;
      try {
        this.rtcManager.observeRemoteVideoFrames(stream, true);
      } catch (error) {
        this.nextRemoteFrameWaiter = null;
        reject(XmaxError.from(error));
        return;
      }
      waiter.timer = setTimeout((): void => {
        if (this.nextRemoteFrameWaiter === waiter) {
          this.finishNextRemoteFrameWait(new XmaxError(
            XmaxErrorCode.TIMEOUT,
            'Remote video next frame timed out'
          ));
        }
      }, REMOTE_NEXT_FRAME_TIMEOUT_MS);
    });
  }

  private finishNextRemoteFrameWait(error?: XmaxError): void {
    const waiter: RemoteFrameWaiter | null = this.nextRemoteFrameWaiter;
    if (waiter === null) {
      return;
    }
    this.nextRemoteFrameWaiter = null;
    clearTimeout(waiter.timer);
    if (error === undefined) {
      waiter.resolve();
    } else {
      waiter.reject(error);
    }
  }

  private async clearFrozenRemoteFrame(): Promise<void> {
    const frame: image.PixelMap | null = this.frozenRemoteFrame;
    this.frozenRemoteFrame = null;
    this.remoteBinding?.setPreviewFrame(undefined);
    if (frame !== null) {
      await frame.release();
    }
  }

  private stopFrameObservation(stream: RemoteStream): void {
    try {
      this.rtcManager.observeRemoteVideoFrames(stream, false);
    } catch (error) {
      XmaxLogger.error(`${XmaxLogger.localized("停止远端视频帧观察失败 (Failed to Stop Remote Video Frame Observation)\n└─ 原因：", "停止远端视频帧观察失败 (Failed to Stop Remote Video Frame Observation)\n└─ Reason: ")}${XmaxError.from(error).message}`, 'Render');
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
