import { XmaxError, XmaxErrorCode } from '../../foundation/errors/XmaxError';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import { ImageSize } from '../../service/media/ImageSize';

/** SDK 支持的实时生成模型。 */
export enum RealtimeModel {

  X2_0 = 'x2.0',

  X2_0_PRO = 'x2.0-pro'
}

/** 实时模型的名称、输入能力与默认媒体规格。 */
export class ModelDefinition {

  /** 服务端识别的模型名称。 */
  readonly name: RealtimeModel;

  /** 支持的固定输入尺寸；非空时必须精确匹配，空数组按像素量和对齐规则计算。 */
  get resolutionBuckets(): ImageSize[] {
    switch (this.name) {
      case RealtimeModel.X2_0:
        return [];
      case RealtimeModel.X2_0_PRO:
        return [
          new ImageSize(1024, 1920),
          new ImageSize(1920, 1024)
        ];
    }
  }

  /** 输入宽高乘积的下限；仅用于没有固定分辨率的模型。 */
  get minimumInputPixels(): number { return 600000; }

  /** 输入宽高乘积的上限；仅用于没有固定分辨率的模型。 */
  get maximumInputPixels(): number {
    switch (this.name) {
      case RealtimeModel.X2_0:
        return 1280000;
      case RealtimeModel.X2_0_PRO:
        return 2100000;
    }
  }

  /** 输入宽高的对齐倍数；仅用于没有固定分辨率的模型。 */
  get inputSizeAlignment(): number { return 32; }

  /** 未指定视频规格时使用的帧率。 */
  get defaultFrameRate(): number {
    switch (this.name) {
      case RealtimeModel.X2_0:
        return 30;
      case RealtimeModel.X2_0_PRO:
        return 30;
    }
  }

  /** 摄像头采集的默认规格。 */
  get defaultCameraVideoFormat(): RealtimeVideoFormat {
    switch (this.name) {
      case RealtimeModel.X2_0:
        return new RealtimeVideoFormat(832, 1472, this.defaultFrameRate);
      case RealtimeModel.X2_0_PRO:
        return new RealtimeVideoFormat(1024, 1920, this.defaultFrameRate);
    }
  }

  /**
   * 创建模型定义。
   *
   * @param name 服务端识别的模型名称。
   */
  constructor(name: RealtimeModel) {
    if (name !== RealtimeModel.X2_0 && name !== RealtimeModel.X2_0_PRO) {
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
