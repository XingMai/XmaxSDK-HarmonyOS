//
//  VideoFrame.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { VideoFormat } from './VideoFormat';
import { VideoFramePlane } from './VideoFramePlane';
import { VideoRotation } from './VideoRotation';

/** A neutral video frame owned by its source. */
export interface VideoFrame {

  /** The video frame format. */
  readonly format: VideoFormat;

  /** The video timestamp, in microseconds. */
  readonly timestampUs: number;

  /** The clockwise frame rotation. */
  readonly rotation: VideoRotation;

  /** The planes in pixel-format order. */
  readonly planes: Array<VideoFramePlane>;
}
