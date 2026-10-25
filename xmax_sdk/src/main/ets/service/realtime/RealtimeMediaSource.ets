//
//  RealtimeMediaSource.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/**
 * A local media source. Cameras use fixed model dimensions; images and videos retain media aspect
 * ratio.
 */
export enum RealtimeMediaSource {

  /** Local camera input. */
  CAMERA = 'camera',

  /** Local image input. */
  IMAGE = 'image',

  /** Local video file input. */
  VIDEO = 'video'
}
