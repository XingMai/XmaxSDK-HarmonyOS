import { ModelDefinition } from './RealtimeModel';

/** 创建实时 Manager 所需的业务配置。 */
export class RealtimeConfiguration {

  /** 实时生成业务使用的模型定义。 */
  readonly model: ModelDefinition;

  /**
   * 创建实时生成业务配置。
   *
   * @param model 实时生成业务使用的模型定义。
   */
  constructor(model: ModelDefinition) {
    this.model = model;
  }
}
