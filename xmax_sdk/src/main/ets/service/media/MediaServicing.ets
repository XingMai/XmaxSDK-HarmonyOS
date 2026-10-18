//
//  MediaServicing.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { RealtimeMediaSource } from '../realtime/RealtimeMediaSource';
import { ImageSize } from './ImageSize';
import { ModelDefinition } from '../../core/realtime/RealtimeModel';

/** 定义与模型输入约束相关的媒体业务规则。 */
export interface MediaServicing {

  /** 模型媒体约束 */
  /** 当前媒体规则使用的模型定义。 */
  readonly model: ModelDefinition;

  /**
   * 本地媒体尺寸；摄像头须匹配模型固定桶，图片和视频不受桶约束。
   *
   * @param size 需要计算或发送的画面尺寸。
   * @param source 媒体输入类型，用于选择尺寸处理规则。
   * @returns 计算得到的媒体宽高。
   */
  resolveMediaSize(size: ImageSize, source: RealtimeMediaSource): ImageSize;

  /**
   * 按媒体比例选择生成画布，保留独立的本地媒体规格。
   *
   * @param size 处理后的本地媒体尺寸，用于确定生成画布的比例。
   * @returns 符合模型固定分辨率桶或像素面积与对齐约束的生成画布尺寸。
   */
  resolveGenerationSize(size: ImageSize): ImageSize;

  /**
   * 按比例计算受宽高上限及可选插帧限制约束的回传尺寸。
   *
   * @param size 需要计算或发送的画面尺寸。
   * @param maximumSize 允许的结果流宽高上限。
   * @param frameInterpolationEnabled 是否将插帧能力纳入目标尺寸约束。
   * @returns 计算得到的媒体宽高。
   */
  resolveTargetSize(size: ImageSize, maximumSize: ImageSize, frameInterpolationEnabled?: boolean): ImageSize;
}
