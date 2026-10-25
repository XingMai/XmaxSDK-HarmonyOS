//
//  InteractionControlling.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import { InteractionFrame } from './InteractionFrame';

/** An interface for generation task interaction input. */
export interface InteractionControlling {

  /**
   * Starts generation task interaction processing.
   *
   * @param taskId The generation task identifier.
   * @param videoFormat The model input format.
   */
  start(
    taskId: string,
    videoFormat: RealtimeVideoFormat
  ): void;

  /** Stops interaction processing. */
  stop(): void;

  /**
   * Submits an interaction frame.
   *
   * @param frame The current viewport touch points and display information.
   */
  submit(
    frame: InteractionFrame
  ): void;
}
