//
//  RealtimeVideoFrameDispatcher.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import { RealtimeVideoFrame, RealtimeVideoFrameListener } from '../../service/realtime/RealtimeVideoFrame';

/** Delivers every frame asynchronously in receive order on the ArkTS event loop without coalescing. */
export class RealtimeVideoFrameDispatcher {

  /** The currently installed event handler. */
  private listener: RealtimeVideoFrameListener | null = null;

  /** The media frames queued for asynchronous consumption. */
  private pendingFrames: RealtimeVideoFrame[] = [];

  /** The timer scheduling pending event delivery. */
  private timer: number = -1;

  /** The revision rejecting obsolete asynchronous delivery. */
  private version: number = 0;

  /** Whether a remote frame listener is installed. */
  get hasListener(): boolean {
    return this.listener !== null;
  }

  /**
   * Replaces the remote frame listener and invalidates pending old frames.
   *
   * @param listener The event handler, or null to remove it.
   */
  setListener(
    listener: RealtimeVideoFrameListener | null
  ): void {
    this.invalidatePendingFrames();
    this.listener = listener;
  }

  /** Clears pending frames and advances the revision to reject obsolete callbacks. */
  invalidatePendingFrames(): void {
    this.version++;
    this.pendingFrames = [];
    if (this.timer !== -1) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
  }

  /**
   * Delivers frames asynchronously, rejecting obsolete frames after listener or lifecycle changes.
   *
   * @param frame The copied remote video frame to enqueue for application delivery.
   */
  dispatch(
    frame: RealtimeVideoFrame
  ): void {
    if (this.listener === null) {
      return;
    }
    this.pendingFrames.push(frame);
    if (this.timer !== -1) {
      return;
    }
    const version: number = this.version;
    this.timer = setTimeout(
      (): void => {
        if (version !== this.version) {
          return;
        }
        this.timer = -1;
        const frames: RealtimeVideoFrame[] = this.pendingFrames;
        this.pendingFrames = [];
        for (const pendingFrame of frames) {
          // A callback can disconnect or replace its listener; invalidate remaining old frames immediately.
          const listener: RealtimeVideoFrameListener | null = this.listener;
          if (version !== this.version || listener === null) {
            return;
          }
          try {
            listener(pendingFrame);
          } catch (error) {
            const reason: string = error instanceof Error ? error.message : String(error);
            XmaxLogger.error(
              `${XmaxLogger.localized("远端视频帧监听器执行失败 (Remote Video Frame Listener Failed)\n└─ 原因：", "远端视频帧监听器执行失败 (Remote Video Frame Listener Failed)\n└─ Reason: ")}${reason}`,
              'Render'
            );
          }
        }
      },
      0
    );
  }
}
