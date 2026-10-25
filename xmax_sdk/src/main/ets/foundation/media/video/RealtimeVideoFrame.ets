//
//  RealtimeVideoFrame.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { VideoFramePlane } from './VideoFramePlane';
import { VideoPixelFormat } from './VideoPixelFormat';
import { VideoRotation } from './VideoRotation';

/** Raw video pixels for remote output or external input, without view cropping or UI overlays. */
export class RealtimeVideoFrame {

  /** The buffer width before rotation, in pixels. */
  readonly width: number;

  /** The buffer height before rotation, in pixels. */
  readonly height: number;

  /** The pixel format; remote output uses I420 and external input accepts NV12 or BGRA. */
  readonly pixelFormat: VideoPixelFormat;

  /**
   * The pixel planes, ordered Y, U, V for I420. SDK-delivered buffers remain valid after callback
   * return.
   */
  readonly planes: VideoFramePlane[];

  /** The realtime video timestamp, in microseconds; not necessarily starting at zero. */
  readonly timestampUs: number;

  /** The clockwise rotation still required for display. */
  readonly rotation: VideoRotation;

  /**
   * Creates a video frame for application delivery.
   *
   * Copies the plane list but retains the plane objects and their pixel buffers.
   */
  constructor(
    width: number,
    height: number,
    pixelFormat: VideoPixelFormat,
    planes: VideoFramePlane[],
    timestampUs: number,
    rotation: VideoRotation
  ) {
    this.width = width;
    this.height = height;
    this.pixelFormat = pixelFormat;
    this.planes = planes.slice();
    this.timestampUs = timestampUs;
    this.rotation = rotation;
  }
}
