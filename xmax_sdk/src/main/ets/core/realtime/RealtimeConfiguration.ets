//
//  RealtimeConfiguration.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { ModelDefinition } from '../../service/realtime/RealtimeModel';

/** The model and adaptive quality settings for a realtime manager. */
export class RealtimeConfiguration {

  /** The model definition used for realtime generation. */
  readonly model: ModelDefinition;

  /**
   * Whether uplink and downlink quality adapt automatically; defaults to true.
   * Disabled connections start at L1 without quality history. Manual adjustments remain available.
   */
  readonly isAdaptiveQualityEnabled: boolean;

  /** Creates a realtime configuration. */
  constructor(
    model: ModelDefinition,
    isAdaptiveQualityEnabled: boolean = true
  ) {
    this.model = model;
    this.isAdaptiveQualityEnabled = isAdaptiveQualityEnabled;
  }
}
