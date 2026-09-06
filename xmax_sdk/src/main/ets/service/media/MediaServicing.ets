import { ImageSize } from './ImageSize';
import { ModelDefinition } from '../../core/realtime/RealtimeModel';

/** 定义与模型输入约束相关的媒体业务规则。 */
export interface MediaServicing {

  /** 当前媒体规则使用的模型定义。 */
  readonly model: ModelDefinition;

  /**
   * 计算满足模型输入约束的尺寸。
   *
   * @param size 原始图片尺寸。
   * @returns 满足模型输入约束的尺寸。
   */
  resolveModelInputSize(
    size: ImageSize
  ): ImageSize;
}
