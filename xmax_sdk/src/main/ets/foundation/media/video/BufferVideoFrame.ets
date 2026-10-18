//
//  BufferVideoFrame.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import {
  XmaxError,
  XmaxErrorCode
} from '../../errors/XmaxError';
import { VideoFormat } from './VideoFormat';
import { VideoFrame } from './VideoFrame';
import { VideoFramePlane } from './VideoFramePlane';
import { VideoRotation } from './VideoRotation';

/** 由 ArrayBuffer 持有像素数据的视频帧。 */
export class BufferVideoFrame implements VideoFrame {

  /** 帧格式与播放时间 */
  readonly format: VideoFormat;
  readonly timestampUs: number;
  readonly rotation: VideoRotation;

  /** 像素平面数据 */
  readonly planes: Array<VideoFramePlane>;

  /**
   * 创建基于缓冲区的视频帧。
   *
   * @param format 需要使用的视频格式。
   * @param timestampUs 媒体帧时间戳，单位微秒。
   * @param planes 按像素格式顺序排列的图像平面。
   * @param rotation 视频画面需要应用的旋转方向。
   * @returns 新建的 BufferVideoFrame 实例。
   */
  constructor(
    format: VideoFormat,
    timestampUs: number,
    planes: Array<VideoFramePlane>,
    rotation: VideoRotation = VideoRotation.ROTATION_0
  ) {
    if (!Number.isFinite(timestampUs) || timestampUs < 0) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Video frame timestamp must be a non-negative finite number'
      );
    }
    if (planes.length === 0) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Video frame must contain at least one plane'
      );
    }

    this.format = format;
    this.timestampUs = timestampUs;
    this.rotation = rotation;
    this.planes = planes.slice();
  }
}
