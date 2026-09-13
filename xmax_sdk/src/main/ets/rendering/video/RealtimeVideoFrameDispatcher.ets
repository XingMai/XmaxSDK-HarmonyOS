import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import { RealtimeVideoFrame, RealtimeVideoFrameListener } from '../../service/realtime/RealtimeVideoFrame';

/** 在 ArkTS 事件循环中按接收顺序异步交付每帧，不合并待交付帧。 */
export class RealtimeVideoFrameDispatcher {
  private listener: RealtimeVideoFrameListener | null = null;
  private pendingFrames: RealtimeVideoFrame[] = [];
  private timer: number = -1;
  private version: number = 0;

  get hasListener(): boolean {
    return this.listener !== null;
  }

  setListener(listener: RealtimeVideoFrameListener | null): void {
    this.invalidatePendingFrames();
    this.listener = listener;
  }

  invalidatePendingFrames(): void {
    this.version++;
    this.pendingFrames = [];
    if (this.timer !== -1) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
  }

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
