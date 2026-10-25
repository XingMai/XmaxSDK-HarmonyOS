//
//  VideoOrientationObserver.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { mediaquery } from '@kit.ArkUI';
import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import { RealtimeVideoTrack, updateRealtimeVideoTrackOrientation } from '../../service/realtime/RealtimeVideoTrack';

/**
 * Observes the component window's orientation rather than inferring rotation from video bounds or
 * device pose.
 */
export class VideoOrientationObserver {

  /** The media query observing window layout orientation. */
  private query: mediaquery.MediaQueryListener | null = null;

  /**
   * Receives window orientation query changes.
   *
   * @param result The media query result containing the current orientation match.
   */
  private listener: ((
    result: mediaquery.MediaQueryResult
  ) => void) | null = null;

  /**
   * Observes track layout orientation and applies its initial value.
   *
   * @param track The SDK video track handle.
   * @param query The view orientation media query.
   */
  start(
    track: RealtimeVideoTrack,
    query: mediaquery.MediaQueryListener
  ): void {
    this.stop();
    const original: RealtimeVideoTrack = RealtimeVideoTrack.resolve(track);
    const listener = (result: mediaquery.MediaQueryResult): void => {
      if (this.listener === listener) {
        updateRealtimeVideoTrackOrientation(
          original,
          result.matches,
          true
        );
      }
    };
    this.query = query;
    this.listener = listener;
    updateRealtimeVideoTrackOrientation(
      original,
      query.matches,
      false
    );
    query.on(
      'change',
      listener
    );
  }

  /** Removes orientation observation and stops updating the track. */
  stop(): void {
    const query = this.query;
    const listener = this.listener;
    this.query = null;
    this.listener = null;
    if (query !== null && listener !== null) {
      try {
        query.off(
          'change',
          listener
        );
      } catch (error) {
        XmaxLogger.error(
          `移除视频方向监听失败 (Failed to Remove Video Orientation Listener)：${String(error)}`,
          'Render'
        );
      }
    }
  }
}
