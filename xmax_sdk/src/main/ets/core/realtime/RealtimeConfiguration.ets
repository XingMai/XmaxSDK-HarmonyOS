//
//  RealtimeConfiguration.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { ModelDefinition } from './RealtimeModel';

/** 创建实时 Manager 所需的业务配置。 */
export class RealtimeConfiguration {

  /** 生成模型配置 */
  /** 实时生成业务使用的模型定义。 */
  readonly model: ModelDefinition;

  /**
   * 创建实时生成业务配置。
   *
   * @param model 实时生成业务使用的模型定义。
   * @returns 新建的 RealtimeConfiguration 实例。
   */
  constructor(model: ModelDefinition) {
    this.model = model;
  }
}
