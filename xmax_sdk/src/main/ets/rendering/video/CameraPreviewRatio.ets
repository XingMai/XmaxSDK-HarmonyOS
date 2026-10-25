//
//  CameraPreviewRatio.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/** A camera preview aspect ratio or container-filling mode. */
export enum CameraPreviewRatio {

  /** A 1:1 camera preview aspect ratio. */
  RATIO_1_1 = '1:1',

  /** A 3:4 camera preview aspect ratio. */
  RATIO_3_4 = '3:4',

  /** A 4:3 camera preview aspect ratio. */
  RATIO_4_3 = '4:3',

  /** A 9:16 camera preview aspect ratio. */
  RATIO_9_16 = '9:16',

  /** A 16:9 camera preview aspect ratio. */
  RATIO_16_9 = '16:9',

  /** Fills the container without a fixed preview ratio. */
  FILL = 'fill'
}
