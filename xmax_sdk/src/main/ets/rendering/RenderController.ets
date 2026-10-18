//
//  RenderController.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { ImageSize } from '../service/media/ImageSize';
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

/** 保存等待远端画面就绪的超时任务和完成回调。 */
class RemoteFrameWaiter {

  /** 首帧等待超时 */
  timer: number = -1;

  /** 首帧等待结果通知 */
  /**
   * 完成当前资源或媒体结果的异步等待。
   *
   * @returns 无返回值。
   */
  readonly resolve: () => void;
  /**
   * 以指定错误结束当前媒体结果的异步等待。
   *
   * @param error 导致当前等待或媒体输出失败的 SDK 错误。
   * @returns 无返回值。
   */
  readonly reject: (error: XmaxError) => void;

  /**
   * 创建远端画面等待记录。
   *
   * @param resolve 操作成功时完成等待的回调。
   * @param reject 操作失败时拒绝等待的回调。
   * @returns 新建的 RemoteFrameWaiter 实例。
   */
  constructor(resolve: () => void, reject: (error: XmaxError) => void) {
    this.resolve = resolve;
    this.reject = reject;
  }
}

/** 统一协调视频轨道、RTC 画面和轨迹交互的渲染资源。 */
export class RenderController implements RenderControlling {

  /** 渲染平台与错误通知 */
  private readonly rtcManager: RtcManaging;
  private readonly errorListener: XmaxErrorListener;

  /** 远端流及其渲染绑定 */
  private remoteBinding: VideoRenderBinding | null = null;
  private remoteStream: RemoteStream | null = null;

  /** 画面就绪与帧交付开关 */
  private remoteFrameReady: boolean = false;
  private remoteFrameDeliveryActive: boolean = false;

  /** 异步帧交付 */
  private readonly frameDispatcher: RealtimeVideoFrameDispatcher = new RealtimeVideoFrameDispatcher();

  /** 首帧等待与错误结果 */
  private remoteFrameError: XmaxError | null = null;
  private readonly remoteFrameWaiters: Set<RemoteFrameWaiter> = new Set();
  private nextRemoteFrameWaiter: RemoteFrameWaiter | null = null;

  /** 冻结预览与资源版本 */
  private frozenRemoteFrame: image.PixelMap | null = null;
  private remoteFreezeVersion: number = 0;

  /** 远端视图绑定控制 */
  private readonly remoteVideoController: RemoteVideoControlling;

  /**
   * 创建渲染层统一 Controller 并完成内部组件装配。
   *
   * @param rtcManager 提供远端视频绑定能力的 RTC Manager。
   * @param errorListener 接收渲染视图异步绑定失败。
   * @returns 新建的 RenderController 实例。
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

  /**
   * 设置公开远端帧监听器；null 取消监听并清除待交付帧。
   *
   * @param listener 接收事件的监听器；可空接口传入 null 时清除监听器。
   * @returns 无返回值。
   */
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

  /**
   * 停止当前流的公开帧交付，直至设置新的远端流。
   *
   * @returns 无返回值。
   */
  stopRemoteVideoFrameDelivery(): void {
    this.remoteFrameDeliveryActive = false;
    this.frameDispatcher.invalidatePendingFrames();
  }

  /**
   * 捕获下一张远端帧并以静态覆盖层冻结当前生成画面。
   *
   * @returns 操作完成时兑现的 Promise。
   */
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

  /**
   * 收到下一张远端帧后移除静态覆盖层。
   *
   * @returns 操作完成时兑现的 Promise。
   */
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
   * 更新当前需要渲染的远端 RTC 视频流。
   *
   * @param stream 远端视频流；传入空值时清除当前流。
   * @returns 无返回值。
   */
  setRemoteStream(stream: RemoteStream | null): void {
    this.resetRemoteFrameWait();
    this.remoteStream = stream;
    this.remoteFrameDeliveryActive = stream !== null;
    this.remoteVideoController.setRemoteStream(stream);
    if (stream !== null) {
      this.rtcManager.observeRemoteVideoFrames(stream, true);
    }
  }

  /**
   * 等待本次 SEI 匹配后出现的首个可用远端帧，超时或流被清除时拒绝。
   *
   * @returns 操作完成时兑现的 Promise。
   */
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

  /**
   * 使启动期间的异步致命错误立即结束首帧等待。
   *
   * @param error 当前操作失败或终止的原因。
   * @returns 无返回值。
   */
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

  /**
   * 清除远端首帧状态，并取消未完成的画面等待。
   *
   * @returns 无返回值。
   */
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

  /**
   * 完成或拒绝全部远端首帧等待，并移除超时任务。
   *
   * @param error 当前操作失败或终止的原因。
   * @returns 无返回值。
   */
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

  /**
   * 等待当前远端流的下一帧可用，超时或中断时拒绝。
   *
   * @returns 操作完成时兑现的 Promise。
   */
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

  /**
   * 完成或拒绝下一帧等待，并释放相关定时器。
   *
   * @param error 当前操作失败或终止的原因。
   * @returns 无返回值。
   */
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

  /**
   * 清除冻结预览并释放所持有的截图资源。
   *
   * @returns 操作完成时兑现的 Promise。
   */
  private async clearFrozenRemoteFrame(): Promise<void> {
    const frame: image.PixelMap | null = this.frozenRemoteFrame;
    this.frozenRemoteFrame = null;
    this.remoteBinding?.setPreviewFrame(undefined);
    if (frame !== null) {
      await frame.release();
    }
  }

  /**
   * 停止对指定远端流的逐帧回调观察。
   *
   * @param stream 需要绑定或处理的媒体流。
   * @returns 无返回值。
   */
  private stopFrameObservation(stream: RemoteStream): void {
    try {
      this.rtcManager.observeRemoteVideoFrames(stream, false);
    } catch (error) {
      XmaxLogger.error(`${XmaxLogger.localized("停止远端视频帧观察失败 (Failed to Stop Remote Video Frame Observation)\n└─ 原因：", "停止远端视频帧观察失败 (Failed to Stop Remote Video Frame Observation)\n└─ Reason: ")}${XmaxError.from(error).message}`, 'Render');
    }
  }

  /**
   * 为远端视频轨道注册画面和轨迹交互绑定。
   *
   * @param track 需要注册的远端视频轨道。
   * @param interactionController 接收轨迹交互输入的统一媒体组件。
   * @param resolvedMediaSize 处理后的本地媒体尺寸，作为独立于回传分辨率的交互基准。
   * @returns 无返回值。
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
      new TrajectoryBinding(interactionController, resolvedMediaSize)
    );
  }

  /**
   * 注销远端轨道的所有渲染绑定并重置远端画面。
   *
   * @param track 需要注销的远端视频轨道；传入空值时仅重置画面。
   * @returns 无返回值。
   */
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
