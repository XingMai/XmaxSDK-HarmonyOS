//
//  BufferVideoFrame.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
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

/** A video frame backed by ArrayBuffer pixel data. */
export class BufferVideoFrame implements VideoFrame {

  /** The frame dimensions and pixel layout. */
  readonly format: VideoFormat;

  /** The frame timestamp, in microseconds. */
  readonly timestampUs: number;

  /** The clockwise video rotation. */
  readonly rotation: VideoRotation;

  /** The pixel planes in the order required by the frame format. */
  readonly planes: Array<VideoFramePlane>;

  /**
   * Creates a buffer-backed video frame.
   *
   * @param format The video format to use.
   * @param timestampUs The media frame timestamp, in microseconds.
   * @param planes The image planes in pixel-format order.
   * @param rotation The rotation to apply to the video image.
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
