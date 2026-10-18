//
//  RealtimeModel.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { XmaxError, XmaxErrorCode } from '../../foundation/errors/XmaxError';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import { ImageSize } from '../../service/media/ImageSize';

/** SDK 支持的实时生成模型。 */
export enum RealtimeModel {

  X2_0 = 'x2.0',

  X2_0_SLA = 'x2.0-sla'
}

/** 实时模型的名称、会话 API 地址、输入能力与默认媒体规格。 */
export class ModelDefinition {

  /** 模型标识 */
  /** 服务端识别的模型名称。 */
  readonly name: RealtimeModel;

  /**
   * 模型专用的会话 API 地址；未配置时沿用客户端环境，不影响存储服务。
   *
   * @returns 模型专用的会话 API 地址；undefined 表示沿用客户端环境的地址。
   */
  get baseURL(): string | undefined {
    return undefined;
  }

  /**
   * 模型生成画布的固定尺寸；摄像头请求须精确匹配，图片和视频保留媒体比例。
   *
   * @returns 模型支持的固定生成画布尺寸；空数组表示使用像素量约束。
   */
  get resolutionBuckets(): ImageSize[] {
    switch (this.name) {
      case RealtimeModel.X2_0:
        return [];
      case RealtimeModel.X2_0_SLA:
        return [
          new ImageSize(1024, 1920),
          new ImageSize(1920, 1024)
        ];
    }
  }

  /**
   * 生成画布像素面积下限；仅用于无固定桶的模型，不放大小尺寸媒体。
   *
   * @returns 生成画布的最小像素面积。
   */
  get minimumInputPixels(): number { return 600000; }

  /**
   * 本地媒体最大像素面积；无固定桶时也限制生成画布。
   *
   * @returns 本地媒体及适用模型生成画布的最大像素面积。
   */
  get maximumInputPixels(): number {
    switch (this.name) {
      case RealtimeModel.X2_0:
        return 1280000;
      case RealtimeModel.X2_0_SLA:
        return 2100000;
    }
  }

  /**
   * 无固定桶时生成画布的宽高对齐倍数；本地媒体统一按 4 对齐。
   *
   * @returns 生成画布宽高需满足的对齐倍数。
   */
  get inputSizeAlignment(): number { return 32; }

  /**
   * 未指定视频规格时使用的帧率。
   *
   * @returns 模型默认使用的视频帧率，单位 fps。
   */
  get defaultFrameRate(): number {
    switch (this.name) {
      case RealtimeModel.X2_0:
        return 30;
      case RealtimeModel.X2_0_SLA:
        return 30;
    }
  }

  /**
   * 摄像头采集的默认规格。
   *
   * @returns 计算或更新后的视频格式。
   */
  get defaultCameraVideoFormat(): RealtimeVideoFormat {
    switch (this.name) {
      case RealtimeModel.X2_0:
        return new RealtimeVideoFormat(832, 1472, this.defaultFrameRate);
      case RealtimeModel.X2_0_SLA:
        return new RealtimeVideoFormat(1024, 1920, this.defaultFrameRate);
    }
  }

  /**
   * 创建模型定义。
   *
   * @param name 服务端识别的模型名称。
   * @returns 新建的 ModelDefinition 实例。
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
