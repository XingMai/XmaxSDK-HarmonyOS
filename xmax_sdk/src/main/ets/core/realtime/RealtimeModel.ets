/** SDK 支持的实时生成模型。 */
export enum RealtimeModel {

  X2_0 = 'x2.0',

  X2_PLATFORM_TESTING = 'x2-platform-testing'
}

/** 表示提交给实时服务的模型定义。 */
export class ModelDefinition {

  /** 服务端识别的模型名称。 */
  readonly name: string;

  /**
   * 创建模型定义。
   *
   * @param name 服务端识别的模型名称。
   */
  constructor(name: string) {
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
