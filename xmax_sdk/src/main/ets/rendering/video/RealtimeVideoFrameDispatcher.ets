import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import { RealtimeVideoFrame, RealtimeVideoFrameListener } from '../../service/realtime/RealtimeVideoFrame';

/** 仅保留最新一帧，避免慢消费者导致待交付帧无限积压。 */
export class RealtimeVideoFrameDispatcher {
  private listener: RealtimeVideoFrameListener | null = null;
  private pendingFrame: RealtimeVideoFrame | null = null;
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
    this.pendingFrame = null;
    if (this.timer !== -1) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
  }

  dispatch(frame: RealtimeVideoFrame): void {
    if (this.listener === null) {
      return;
    }
    this.pendingFrame = frame;
    if (this.timer !== -1) {
      return;
    }
    const version: number = this.version;
    this.timer = setTimeout((): void => {
      if (version !== this.version) {
        return;
      }
      this.timer = -1;
      const frame: RealtimeVideoFrame | null = this.pendingFrame;
      const listener: RealtimeVideoFrameListener | null = this.listener;
      this.pendingFrame = null;
      if (frame === null || listener === null) {
        return;
      }
      try {
        listener(frame);
      } catch (error) {
        const reason: string = error instanceof Error ? error.message : String(error);
        XmaxLogger.error(`远端视频帧监听器执行失败\n└─ 原因：${reason}`, 'Render');
      }
    }, 0);
  }
}
