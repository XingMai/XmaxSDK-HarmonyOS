import { RealtimeMediaSource } from '../realtime/RealtimeMediaSource';
import { ImageSize } from './ImageSize';
import { ModelDefinition } from '../../core/realtime/RealtimeModel';

/** 定义与模型输入约束相关的媒体业务规则。 */
export interface MediaServicing {

  /** 当前媒体规则使用的模型定义。 */
  readonly model: ModelDefinition;

  /** 本地媒体尺寸；摄像头须匹配模型固定桶，图片和视频不受桶约束。 */
  resolveMediaSize(size: ImageSize, source: RealtimeMediaSource): ImageSize;

  /** 按媒体比例选择生成画布，保留独立的本地媒体规格。 */
  resolveGenerationSize(size: ImageSize): ImageSize;

  /** 按比例计算受宽高上限及可选插帧限制约束的回传尺寸。 */
  resolveTargetSize(size: ImageSize, maximumSize: ImageSize, frameInterpolationEnabled?: boolean): ImageSize;

  /**
   * @deprecated 使用 resolveMediaSize 或 resolveGenerationSize。
   * 固定分辨率必须精确匹配；其他模型按像素量与对齐约束计算尺寸。
   *
   * @param size 原始图片尺寸。
   * @returns 满足模型输入约束的尺寸。
   */
  resolveModelInputSize(
    size: ImageSize
  ): ImageSize;
}
