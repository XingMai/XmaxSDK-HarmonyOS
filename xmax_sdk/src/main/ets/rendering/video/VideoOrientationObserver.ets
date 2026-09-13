import { mediaquery } from '@kit.ArkUI';
import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import { RealtimeVideoTrack, updateRealtimeVideoTrackOrientation } from '../../service/realtime/RealtimeVideoTrack';

/** 监听组件所在窗口的方向，不使用视频容器尺寸或设备姿态推断转屏。 */
export class VideoOrientationObserver {
  private query: mediaquery.MediaQueryListener | null = null;
  private listener: ((result: mediaquery.MediaQueryResult) => void) | null = null;

  start(track: RealtimeVideoTrack, query: mediaquery.MediaQueryListener): void {
    this.stop();
    const original: RealtimeVideoTrack = RealtimeVideoTrack.resolve(track);
    const listener = (result: mediaquery.MediaQueryResult): void => {
      if (this.listener === listener) {
        updateRealtimeVideoTrackOrientation(original, result.matches, true);
      }
    };
    this.query = query;
    this.listener = listener;
    updateRealtimeVideoTrackOrientation(original, query.matches, false);
    query.on('change', listener);
  }

  stop(): void {
    const query = this.query;
    const listener = this.listener;
    this.query = null;
    this.listener = null;
    if (query !== null && listener !== null) {
      try {
        query.off('change', listener);
      } catch (error) {
        XmaxLogger.error(`移除视频方向监听失败 (Failed to Remove Video Orientation Listener)：${String(error)}`, 'Render');
      }
    }
  }
}
