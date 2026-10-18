//
//  EncodingControlling.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';

/** 定义视频编码参数的配置能力。 */
export interface EncodingControlling {

  /**
   * 配置视频编码参数。
   *
   * @param videoFormat 视频编码格式。
   * @returns 无返回值。
   */
  configure(
    videoFormat: RealtimeVideoFormat
  ): void;
}
