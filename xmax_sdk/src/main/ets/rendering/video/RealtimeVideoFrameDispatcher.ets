//
//  RealtimeVideoFrameDispatcher.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import { RealtimeVideoFrame, RealtimeVideoFrameListener } from '../../service/realtime/RealtimeVideoFrame';

/** 在 ArkTS 事件循环中按接收顺序异步交付每帧，不合并待交付帧。 */
export class RealtimeVideoFrameDispatcher {

  /** 业务帧监听器 */
  private listener: RealtimeVideoFrameListener | null = null;

  /** 待交付帧及其调度 */
  private pendingFrames: RealtimeVideoFrame[] = [];
  private timer: number = -1;

  /** 过期通知隔离 */
  private version: number = 0;

  /**
   * 判断是否已设置远端视频帧监听器。
   *
   * @returns 监听器已设置时返回 true。
   */
  get hasListener(): boolean {
    return this.listener !== null;
  }

  /**
   * 替换远端视频帧监听器，并使尚未交付的旧帧失效。
   *
   * @param listener 接收事件的监听器；可空接口传入 null 时清除监听器。
   * @returns 无返回值。
   */
  setListener(listener: RealtimeVideoFrameListener | null): void {
    this.invalidatePendingFrames();
    this.listener = listener;
  }

  /**
   * 清除待交付帧并更新版本，阻止旧回调继续送达。
   *
   * @returns 无返回值。
   */
  invalidatePendingFrames(): void {
    this.version++;
    this.pendingFrames = [];
    if (this.timer !== -1) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
  }

  /**
   * 异步交付远端视频帧，并在监听器或生命周期变化后丢弃旧帧。
   *
   * @param frame 需要处理或交付的媒体帧。
   * @returns 无返回值。
   */
  dispatch(frame: RealtimeVideoFrame): void {
    if (this.listener === null) {
      return;
    }
    this.pendingFrames.push(frame);
    if (this.timer !== -1) {
      return;
    }
    const version: number = this.version;
    this.timer = setTimeout((): void => {
      if (version !== this.version) {
        return;
      }
      this.timer = -1;
      const frames: RealtimeVideoFrame[] = this.pendingFrames;
      this.pendingFrames = [];
      for (const pendingFrame of frames) {
        // 监听器可能在回调内断开连接或替换自己，剩余旧帧必须立即失效。
        const listener: RealtimeVideoFrameListener | null = this.listener;
        if (version !== this.version || listener === null) {
          return;
        }
        try {
          listener(pendingFrame);
        } catch (error) {
          const reason: string = error instanceof Error ? error.message : String(error);
          XmaxLogger.error(`${XmaxLogger.localized("远端视频帧监听器执行失败 (Remote Video Frame Listener Failed)\n└─ 原因：", "远端视频帧监听器执行失败 (Remote Video Frame Listener Failed)\n└─ Reason: ")}${reason}`, 'Render');
        }
      }
    }, 0);
  }
}
