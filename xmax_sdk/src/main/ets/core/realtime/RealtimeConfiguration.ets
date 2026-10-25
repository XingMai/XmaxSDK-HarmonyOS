//
//  RealtimeConfiguration.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { ModelDefinition } from './RealtimeModel';

/** The configuration for creating a realtime manager. */
export class RealtimeConfiguration {

  /** The model definition used for realtime generation. */
  readonly model: ModelDefinition;

  /** Creates a realtime configuration. */
  constructor(
    model: ModelDefinition
  ) {
    this.model = model;
  }
}
