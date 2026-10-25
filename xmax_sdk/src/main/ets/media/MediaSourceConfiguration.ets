//
//  MediaSourceConfiguration.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { RealtimeVideoFormat } from '../service/realtime/RealtimeVideoFormat';

/** The video format and audio availability of local file media. */
export class MediaSourceConfiguration {

  /** The current video dimensions, frame rate, and encoding settings. */
  readonly videoFormat: RealtimeVideoFormat;

  /** Whether the media source includes an available audio track. */
  readonly hasAudio: boolean;

  /** Creates a local file media configuration. */
  constructor(
    videoFormat: RealtimeVideoFormat,
    hasAudio: boolean
  ) {
    this.videoFormat = videoFormat;
    this.hasAudio = hasAudio;
  }
}
