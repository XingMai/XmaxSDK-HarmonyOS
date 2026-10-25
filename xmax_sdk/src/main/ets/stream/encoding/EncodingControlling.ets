//
//  EncodingControlling.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';

/** An interface for video encoder configuration. */
export interface EncodingControlling {

  /**
   * Configures video encoding.
   *
   * @param videoFormat The video encoding format.
   */
  configure(
    videoFormat: RealtimeVideoFormat
  ): void;
}
