//
//  VideoContentMode.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/** The video fitting mode within a rendering container. */
export enum VideoContentMode {

  /** Preserves the entire image's aspect ratio, allowing empty space. */
  FIT = 'fit',

  /** Fills the container while preserving aspect ratio, allowing cropping. */
  FILL = 'fill'
}
