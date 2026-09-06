import { XmaxError, XmaxErrorCode } from '../../foundation/errors/XmaxError';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import { RealtimeMediaSource } from './RealtimeMediaSource';

/** SDK 支持的实时生成模型。 */
export enum RealtimeModel {

  X2_0 = 'x2.0',

  X2_0_SLA = 'x2.0-sla'
}

/** 实时模型的名称、输入能力与默认媒体规格。 */
export class ModelDefinition {

  /** 服务端识别的模型名称。 */
  readonly name: RealtimeModel;

  /** 模型支持的本地媒体来源；返回独立集合，修改它不会改变模型能力。 */
  get supportedMediaSources(): Set<RealtimeMediaSource> {
    return new Set(this.name === RealtimeModel.X2_0_SLA ?
      [RealtimeMediaSource.CAMERA] :
      [RealtimeMediaSource.CAMERA, RealtimeMediaSource.VIDEO, RealtimeMediaSource.IMAGE]);
  }

  /** 输入宽高乘积的下限。 */
  get minimumInputPixels(): number { return 600000; }

  /** 输入宽高乘积的上限。 */
  get maximumInputPixels(): number {
    return this.name === RealtimeModel.X2_0_SLA ? 2100000 : 1280000;
  }

  /** 输入宽度和高度分别需要对齐的像素倍数。 */
  get inputSizeAlignment(): number { return 32; }

  /** 未指定视频规格时使用的帧率。 */
  get defaultFrameRate(): number {
    return this.name === RealtimeModel.X2_0_SLA ? 30 : 24;
  }

  /** 摄像头采集的默认规格。 */
  get defaultCameraVideoFormat(): RealtimeVideoFormat {
    return this.name === RealtimeModel.X2_0_SLA ?
      new RealtimeVideoFormat(1024, 1920, this.defaultFrameRate) :
      new RealtimeVideoFormat(832, 1472, this.defaultFrameRate);
  }

  /**
   * 创建模型定义。
   *
   * @param name 服务端识别的模型名称。
   */
  constructor(name: RealtimeModel) {
    if (name !== RealtimeModel.X2_0 && name !== RealtimeModel.X2_0_SLA) {
      throw new XmaxError(XmaxErrorCode.INVALID_CONFIGURATION, `Unsupported realtime model: ${name}`);
    }
    this.name = name;
  }
}

/** 提供实时生成模型定义的创建入口。 */
export class RealtimeModels {

  /**
   * 根据 SDK 模型枚举创建实时生成模型定义。
   *
   * @param model SDK 支持的实时生成模型。
   * @returns 可用于创建 `RealtimeConfiguration` 的模型定义。
   */
  static realtime(model: RealtimeModel): ModelDefinition {
    return new ModelDefinition(model);
  }
}
