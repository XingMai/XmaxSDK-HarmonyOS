//
//  ImageSourceControlling.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { image } from '@kit.ImageKit';
import { XmaxError } from '../../foundation/errors/XmaxError';
import { VideoFrame } from '../../foundation/media/video/VideoFrame';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';

/**
 * Receives repeated image frames at the target rate.
 *
 * @param frame The video frame containing the prepared local image at the current output timestamp.
 */
export type ImageSourceFrameListener = (
  frame: VideoFrame
) => void;

/**
 * Receives image preparation or frame output errors.
 *
 * @param error The local image preparation or frame output failure.
 */
export type ImageSourceErrorListener = (
  error: XmaxError
) => void;

/** An interface for continuous local image frame output. */
export interface ImageSourceControlling {

  /**
   * Prepares an image and output format.
   *
   * @param source A local file path, encoded image bytes, or platform PixelMap.
   * @param videoFormat The requested format, resolved from image dimensions if omitted.
   *
   * @returns The resolved image output format.
   */
  prepare(
    source: string | ArrayBuffer | Uint8Array | image.PixelMap,
    videoFormat?: RealtimeVideoFormat
  ): Promise<RealtimeVideoFormat>;

  /** Starts image frame output at the target rate. */
  start(): void;

  /** Stops output and releases image resources. */
  stop(): void;
}
