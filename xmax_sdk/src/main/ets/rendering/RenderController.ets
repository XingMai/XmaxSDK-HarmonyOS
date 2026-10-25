//
//  RenderController.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { ImageSize } from '../service/media/ImageSize';
import { RealtimeVideoFrame, RealtimeVideoFrameListener } from '../service/realtime/RealtimeVideoFrame';
import { RealtimeMediaFrameListener } from '../service/realtime/RealtimeMediaFrame';
import { image } from '@kit.ImageKit';
import { RealtimeVideoFrameDispatcher } from './video/RealtimeVideoFrameDispatcher';
import { RealtimeMediaFrameDispatcher } from './video/RealtimeMediaFrameDispatcher';
import { RtcRemoteAudioFrame } from '../foundation/rtc/RtcRemoteAudioFrame';
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

/** A remote first-frame wait with its timeout and completion handlers. */
class RemoteFrameWaiter {

  // First-frame timeout

  /** The timer scheduling pending event delivery. */
  timer: number = -1;

  /** Completes an asynchronous resource or media result wait. */
  readonly resolve: () => void;

  /**
   * Rejects the current media result wait with an error.
   *
   * @param error The SDK error ending the wait or media output.
   */
  readonly reject: (
    error: XmaxError
  ) => void;

  /** Creates a remote frame waiter. */
  constructor(
    resolve: () => void,
    reject: (
      error: XmaxError
    ) => void
  ) {
    this.resolve = resolve;
    this.reject = reject;
  }
}

/** Coordinates video tracks, RTC rendering, and trajectory rendering resources. */
export class RenderController implements RenderControlling {

  // Rendering platform and error delivery

  /** The adapter for RTC engine, room, and media services. */
  private readonly rtcManager: RtcManaging;

  /** The handler for asynchronous component failures. */
  private readonly errorListener: XmaxErrorListener;

  // Remote stream and rendering binding

  /** The rendering resources registered for the remote track. */
  private remoteBinding: VideoRenderBinding | null = null;

  /** The current remote result stream. */
  private remoteStream: RemoteStream | null = null;

  // Video readiness and frame observation

  /** Whether a usable result frame has arrived for this binding. */
  private remoteFrameReady: boolean = false;

  /** Whether public frame delivery is enabled for the result binding. */
  private remoteFrameDeliveryActive: boolean = false;

  // Asynchronous frame delivery

  /** The queue delivering copied frames to your app asynchronously. */
  private readonly frameDispatcher: RealtimeVideoFrameDispatcher = new RealtimeVideoFrameDispatcher();

  /** The bounded queue delivering unified PCM and video events. */
  private readonly mediaFrameDispatcher: RealtimeMediaFrameDispatcher = new RealtimeMediaFrameDispatcher();

  // First-frame wait and error result

  /** The fatal error ending pending remote frame waits. */
  private remoteFrameError: XmaxError | null = null;

  /** The pending remote first-frame waits. */
  private readonly remoteFrameWaiters: Set<RemoteFrameWaiter> = new Set();

  /** The pending next-frame wait used to resume frozen video. */
  private nextRemoteFrameWaiter: RemoteFrameWaiter | null = null;

  // Frozen preview and resource revision

  /** The retained snapshot displayed while remote video is frozen. */
  private frozenRemoteFrame: image.PixelMap | null = null;

  /** The revision rejecting stale freeze and resume results. */
  private remoteFreezeVersion: number = 0;

  // Remote view binding controller

  /** The controller binding remote streams to native views. */
  private readonly remoteVideoController: RemoteVideoControlling;

  /**
   * Creates a render controller and its components.
   *
   * @param rtcManager The RTC manager binding remote video.
   * @param errorListener The asynchronous view binding failure handler.
   */
  constructor(
    rtcManager: RtcManaging,
    errorListener: XmaxErrorListener = (_error: XmaxError): void => { }
  ) {
    this.rtcManager = rtcManager;
    this.errorListener = errorListener;
    this.remoteVideoController = new RemoteVideoController(
      rtcManager,
      (ready: boolean): void => {
        this.remoteBinding?.setVideoReady(ready);
      }
    );

    rtcManager.setRemoteVideoFrameListener((stream: RemoteStream, copyFrame: () => RealtimeVideoFrame): void => {
      if (this.remoteStream?.key() !== stream.key() || this.remoteFrameError !== null) {
        return;
      }

      if (!this.remoteFrameReady) {
        this.remoteFrameReady = true;
        this.finishRemoteFrameWaiters();
      }
      // Resume needs only a next-frame notification; copy pixels only for the public listener.
      this.finishNextRemoteFrameWait();

      const shouldDeliver: boolean = (this.frameDispatcher.hasListener ||
        this.mediaFrameDispatcher.hasListener) && this.remoteFrameDeliveryActive;
      if (!shouldDeliver) {
        this.stopFrameObservation(stream);
        return;
      }

      try {
        const streamId: string | undefined = this.mediaFrameDispatcher.streamId;
        const frame: RealtimeVideoFrame = copyFrame();
        this.frameDispatcher.dispatch(frame);
        if (streamId !== undefined) {
          this.mediaFrameDispatcher.dispatchVideo(
            frame,
            streamId
          );
        }
      } catch (error) {
        XmaxLogger.error(
          `${XmaxLogger.localized("复制远端视频帧失败 (Remote Video Frame Copy Failed)\n└─ 原因：", "复制远端视频帧失败 (Remote Video Frame Copy Failed)\n└─ Reason: ")}${XmaxError.from(error).message}`,
          'Render'
        );
      }
    });

    rtcManager.setRemoteAudioFrameListener((stream: RemoteStream, copyFrame: () => RtcRemoteAudioFrame): void => {
      const streamId: string | undefined = this.mediaFrameDispatcher.streamId;
      if (this.remoteStream?.key() !== stream.key() || !this.remoteFrameDeliveryActive ||
        this.remoteFrameError !== null || !this.mediaFrameDispatcher.hasListener || streamId === undefined) {
        return;
      }

      try {
        this.mediaFrameDispatcher.dispatchAudio(
          copyFrame(),
          streamId
        );
      } catch (error) {
        XmaxLogger.error(
          'Remote audio frame copy failed: ' + String(error),
          'Render'
        );
      }
    });
  }

  /**
   * Sets remote frame delivery; null removes the listener and clears pending frames.
   *
   * @param listener The event handler, or null to remove it.
   */
  setRemoteVideoFrameListener(
    listener: RealtimeVideoFrameListener | null
  ): void {
    const stream: RemoteStream | null = this.remoteStream;
    // Enable observation first; preserve the existing listener and pending frames if enabling fails.
    if (listener !== null && stream !== null && this.remoteFrameDeliveryActive && this.remoteFrameError === null) {
      this.rtcManager.observeRemoteVideoFrames(
        stream,
        true
      );
    }

    this.frameDispatcher.setListener(listener);
    if (listener === null && !this.mediaFrameDispatcher.hasListener && stream !== null &&
      this.remoteFrameReady && this.nextRemoteFrameWaiter === null) {
      this.stopFrameObservation(stream);
    }
  }

  /** Enables media observation before replacing a receiver, retaining it on configuration failure. */
  setRemoteMediaFrameListener(
    listener: RealtimeMediaFrameListener | null
  ): void {
    const stream: RemoteStream | null = this.remoteStream;
    if (listener !== null && stream !== null && this.remoteFrameDeliveryActive && this.remoteFrameError === null) {
      this.rtcManager.observeRemoteVideoFrames(
        stream,
        true
      );
      try {
        this.rtcManager.observeRemoteAudioFrames(
          stream,
          true
        );
      } catch (error) {
        if (!this.frameDispatcher.hasListener && !this.mediaFrameDispatcher.hasListener &&
          this.remoteFrameReady && this.nextRemoteFrameWaiter === null) {
          this.stopFrameObservation(stream);
        }
        throw XmaxError.from(error);
      }
    }

    this.mediaFrameDispatcher.setListener(listener);
    if (listener === null && stream !== null) {
      this.stopAudioFrameObservation(stream);
      if (!this.frameDispatcher.hasListener && this.remoteFrameReady && this.nextRemoteFrameWaiter === null) {
        this.stopFrameObservation(stream);
      }
    }
  }

  /** Stops all public remote frame delivery until a new result stream is set. */
  stopRemoteFrameDelivery(): void {
    this.remoteFrameDeliveryActive = false;
    this.frameDispatcher.invalidatePendingFrames();
    this.mediaFrameDispatcher.setStream(false);

    if (this.remoteStream !== null) {
      this.stopAudioFrameObservation(this.remoteStream);
    }
  }

  /** Captures the next remote frame as a frozen result overlay. */
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

  /** Removes the frozen overlay after the next remote frame arrives. */
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

  /**
   * Updates the remote RTC stream to render.
   *
   * @param stream The remote stream, or null to clear it.
   */
  setRemoteStream(
    stream: RemoteStream | null
  ): void {
    this.resetRemoteFrameWait();
    this.remoteStream = stream;
    this.remoteFrameDeliveryActive = stream !== null;
    this.mediaFrameDispatcher.setStream(stream !== null);
    this.remoteVideoController.setRemoteStream(stream);

    if (stream !== null) {
      this.rtcManager.observeRemoteVideoFrames(
        stream,
        true
      );
      if (this.mediaFrameDispatcher.hasListener) {
        this.rtcManager.observeRemoteAudioFrames(
          stream,
          true
        );
      }
    }
  }

  /** Waits for a usable frame after the current SEI match, rejecting on timeout or stream removal. */
  waitUntilRemoteFrameReady(): Promise<void> {
    if (this.remoteStream === null) {
      return Promise.reject(new XmaxError(
        XmaxErrorCode.CANCELLED,
        'Remote video first frame wait was cancelled'
      ));
    }
    if (this.remoteFrameError !== null) {
      return Promise.reject(this.remoteFrameError);
    }
    if (this.remoteFrameReady) {
      return Promise.resolve();
    }

    return new Promise<void>((resolve: () => void, reject: (
      error: XmaxError
    ) => void): void => {
      const waiter = new RemoteFrameWaiter(
        resolve,
        reject
      );
      this.remoteFrameWaiters.add(waiter);
      waiter.timer = setTimeout(
        (): void => {
          if (this.remoteFrameWaiters.has(waiter)) {
            this.failRemoteFrameWait(new XmaxError(
              XmaxErrorCode.TIMEOUT,
              'Remote video first frame timed out'
            ));
          }
        },
        REMOTE_FRAME_TIMEOUT_MS
      );
    });
  }

  /**
   * Ends a startup frame wait immediately on a fatal asynchronous error.
   *
   * @param error The fatal failure rejecting the pending first-frame wait.
   */
  failRemoteFrameWait(
    error: XmaxError
  ): void {
    if (this.remoteStream === null || this.remoteFrameReady || this.remoteFrameError !== null) {
      return;
    }

    this.stopRemoteFrameDelivery();
    this.remoteFrameError = error;
    this.stopFrameObservation(this.remoteStream);
    this.finishRemoteFrameWaiters(error);
    this.finishNextRemoteFrameWait(error);
  }

  /** Clears remote readiness and cancels pending frame waits. */
  private resetRemoteFrameWait(): void {
    ++this.remoteFreezeVersion;
    this.stopRemoteFrameDelivery();

    const stream: RemoteStream | null = this.remoteStream;
    this.remoteStream = null;
    this.remoteFrameReady = false;
    this.remoteFrameError = null;

    this.finishNextRemoteFrameWait(new XmaxError(
      XmaxErrorCode.CANCELLED,
      'Remote video next frame wait was cancelled'
    ));
    void this.clearFrozenRemoteFrame();
    this.finishRemoteFrameWaiters(new XmaxError(
      XmaxErrorCode.CANCELLED,
      'Remote video first frame wait was cancelled'
    ));

    if (stream !== null) {
      this.stopFrameObservation(stream);
    }
  }

  /**
   * Completes or rejects all first-frame waiters and removes timeouts.
   *
   * @param error The failure rejecting all first-frame waits; omission completes them successfully.
   */
  private finishRemoteFrameWaiters(
    error?: XmaxError
  ): void {
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

  /** Waits for the current stream's next frame, rejecting on timeout or interruption. */
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
      reject: (
        error: XmaxError
      ) => void
    ): void => {
      const waiter = new RemoteFrameWaiter(
        resolve,
        reject
      );
      this.nextRemoteFrameWaiter = waiter;
      try {
        this.rtcManager.observeRemoteVideoFrames(
          stream,
          true
        );
      } catch (error) {
        this.nextRemoteFrameWaiter = null;
        reject(XmaxError.from(error));
        return;
      }

      waiter.timer = setTimeout(
        (): void => {
          if (this.nextRemoteFrameWaiter === waiter) {
            this.finishNextRemoteFrameWait(new XmaxError(
              XmaxErrorCode.TIMEOUT,
              'Remote video next frame timed out'
            ));
          }
        },
        REMOTE_NEXT_FRAME_TIMEOUT_MS
      );
    });
  }

  /**
   * Completes or rejects the next-frame wait and releases timers.
   *
   * @param error The failure rejecting the next-frame wait; omission completes it successfully.
   */
  private finishNextRemoteFrameWait(
    error?: XmaxError
  ): void {
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

  /** Clears frozen preview and releases its snapshot. */
  private async clearFrozenRemoteFrame(): Promise<void> {
    const frame: image.PixelMap | null = this.frozenRemoteFrame;
    this.frozenRemoteFrame = null;
    this.remoteBinding?.setPreviewFrame(undefined);

    if (frame !== null) {
      await frame.release();
    }
  }

  /**
   * Stops frame observation for a remote stream.
   *
   * @param stream The media stream to bind or process.
   */
  private stopFrameObservation(
    stream: RemoteStream
  ): void {
    try {
      this.rtcManager.observeRemoteVideoFrames(
        stream,
        false
      );
    } catch (error) {
      XmaxLogger.error(
        `${XmaxLogger.localized("停止远端视频帧观察失败 (Failed to Stop Remote Video Frame Observation)\n└─ 原因：", "停止远端视频帧观察失败 (Failed to Stop Remote Video Frame Observation)\n└─ Reason: ")}${XmaxError.from(error).message}`,
        'Render'
      );
    }
  }

  /** Disables PCM delivery without letting observation cleanup block result teardown. */
  private stopAudioFrameObservation(
    stream: RemoteStream
  ): void {
    try {
      this.rtcManager.observeRemoteAudioFrames(
        stream,
        false
      );
    } catch (error) {
      XmaxLogger.error(
        'Remote audio frame observation cleanup failed: ' + String(error),
        'Render'
      );
    }
  }

  /**
   * Registers rendering and interaction bindings for a remote track.
   *
   * @param track The remote track to register.
   * @param interactionController The media component receiving trajectory interactions.
   * @param resolvedMediaSize The processed local media dimensions defining interaction coordinates
   * independently of return resolution.
   */
  registerRemoteTrack(
    track: RealtimeVideoTrack,
    interactionController: InteractionControlling,
    resolvedMediaSize: ImageSize
  ): void {
    const binding = new VideoRenderBinding(
      this.rtcManager.renderLibraryName(),
      (
        viewId: string,
        contentMode: VideoContentMode
      ): void => {
        try {
          this.remoteVideoController.attach(
            viewId,
            contentMode
          );
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
    VideoRenderRegistry.register(
      track,
      binding
    );

    TrajectoryRegistry.register(
      track,
      new TrajectoryBinding(
        interactionController,
        resolvedMediaSize
      )
    );
  }

  /**
   * Unregisters remote track bindings and resets remote video.
   *
   * @param track The track to unregister; an absent track only resets video.
   */
  resetRemoteTrack(
    track: RealtimeVideoTrack | null
  ): void {
    this.resetRemoteFrameWait();
    if (track !== null) {
      VideoRenderRegistry.unregister(track);
      TrajectoryRegistry.unregister(track);
    }

    this.remoteVideoController.reset();
    this.remoteBinding = null;
  }
}
