//
//  MediaSourceConfiguration.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { RealtimeVideoFormat } from '../service/realtime/RealtimeVideoFormat';

/** 描述本地文件媒体使用的视频格式及是否包含音频。 */
export class MediaSourceConfiguration {

  /** 文件媒体输出规格 */
  readonly videoFormat: RealtimeVideoFormat;
  readonly hasAudio: boolean;

  /**
   * 创建本地文件媒体配置。
   *
   * @param videoFormat 媒体输出或传输所需的视频规格。
   * @param hasAudio 媒体源是否包含可播放或发布的音轨。
   * @returns 新建的 MediaSourceConfiguration 实例。
   */
  constructor(
    videoFormat: RealtimeVideoFormat,
    hasAudio: boolean
  ) {
    this.videoFormat = videoFormat;
    this.hasAudio = hasAudio;
  }
}
