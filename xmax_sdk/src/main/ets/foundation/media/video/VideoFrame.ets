//
//  VideoFrame.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { VideoFormat } from './VideoFormat';
import { VideoFramePlane } from './VideoFramePlane';
import { VideoRotation } from './VideoRotation';

/** 表示由视频源持有的中性视频帧。 */
export interface VideoFrame {

  /** 帧格式与播放时间 */
  /** 视频帧格式。 */
  readonly format: VideoFormat;

  /** 视频帧时间戳，单位为微秒。 */
  readonly timestampUs: number;

  /** 视频帧顺时针旋转角度。 */
  readonly rotation: VideoRotation;

  /** 像素平面数据 */
  /** 按像素格式约定排列的数据平面。 */
  readonly planes: Array<VideoFramePlane>;
}
