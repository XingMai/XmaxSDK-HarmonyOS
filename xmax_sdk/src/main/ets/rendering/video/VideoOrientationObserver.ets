//
//  VideoOrientationObserver.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { mediaquery } from '@kit.ArkUI';
import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import { RealtimeVideoTrack, updateRealtimeVideoTrackOrientation } from '../../service/realtime/RealtimeVideoTrack';

/** 监听组件所在窗口的方向，不使用视频容器尺寸或设备姿态推断转屏。 */
export class VideoOrientationObserver {

  /** 布局方向查询与监听 */
  private query: mediaquery.MediaQueryListener | null = null;
  /**
   * 接收组件持有的状态或媒体结果通知。
   *
   * @param result 包含当前横竖屏匹配状态的媒体查询结果。
   * @returns 无返回值。
   */
  private listener: ((result: mediaquery.MediaQueryResult) => void) | null = null;

  /**
   * 订阅指定视频轨道的布局方向变化，并同步初始方向。
   *
   * @param track SDK 返回的视频轨道句柄。
   * @param query 监听视图横竖屏布局的媒体查询对象。
   * @returns 无返回值。
   */
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

  /**
   * 解除方向查询监听，停止更新轨道方向。
   *
   * @returns 无返回值。
   */
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
