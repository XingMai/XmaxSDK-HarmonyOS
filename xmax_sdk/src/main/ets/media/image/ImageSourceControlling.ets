//
//  ImageSourceControlling.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { image } from '@kit.ImageKit';
import { XmaxError } from '../../foundation/errors/XmaxError';
import { VideoFrame } from '../../foundation/media/video/VideoFrame';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';

/**
 * 接收图片源按目标帧率重复输出的视频帧。
 *
 * @param frame 需要处理或交付的媒体帧。
 * @returns 无返回值。
 */
export type ImageSourceFrameListener = (frame: VideoFrame) => void;

/**
 * 接收图片源准备或帧输出失败的错误。
 *
 * @param error 当前操作失败或终止的原因。
 * @returns 无返回值。
 */
export type ImageSourceErrorListener = (error: XmaxError) => void;

/** 定义本地图片持续输出视频帧的能力。 */
export interface ImageSourceControlling {

  /**
   * 准备图片和输出格式。
   *
   * @param source 本地文件路径、图片编码数据或平台 PixelMap。
   * @param videoFormat 期望的视频输出格式；未传入时根据图片尺寸自动计算。
   * @returns 图片实际使用的视频输出格式。
   */
  prepare(
    source: string | ArrayBuffer | Uint8Array | image.PixelMap,
    videoFormat?: RealtimeVideoFormat
  ): Promise<RealtimeVideoFormat>;

  /**
   * 开始按目标帧率持续输出图片帧。
   *
   * @returns 无返回值。
   */
  start(): void;

  /**
   * 停止输出并释放图片资源。
   *
   * @returns 无返回值。
   */
  stop(): void;
}
