//
//  RealtimeMediaStream.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { RealtimeVideoTrack } from './RealtimeVideoTrack';

/** 组合媒体流标识与视频轨道，供连接、生成和视图展示使用。 */
export class RealtimeMediaStream {

  /** 媒体流身份与视频轨道 */
  readonly id: string;
  readonly videoTrack?: RealtimeVideoTrack;

  /**
   * 创建实时媒体流。
   *
   * @param id 当前资源的唯一标识。
   * @param videoTrack 媒体流提供的视频轨道句柄。
   * @returns 新建的 RealtimeMediaStream 实例。
   */
  constructor(
    id: string,
    videoTrack?: RealtimeVideoTrack
  ) {
    this.id = id;
    this.videoTrack = videoTrack;
  }
}
