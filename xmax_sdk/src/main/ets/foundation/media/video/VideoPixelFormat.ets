//
//  VideoPixelFormat.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/** A pixel format supported by neutral video frames. */
export enum VideoPixelFormat {

  /** Planar YUV 4:2:0 with Y, U, and V planes. */
  I420 = 'i420',

  /** Semiplanar YUV 4:2:0 with interleaved UV. */
  NV12 = 'nv12',

  /** Semiplanar YUV 4:2:0 with interleaved VU. */
  NV21 = 'nv21',

  /** Packed red, green, blue, and alpha channels. */
  RGBA = 'rgba',

  /** Packed blue, green, red, and alpha channels. */
  BGRA = 'bgra',

  /** Packed alpha, red, green, and blue channels. */
  ARGB = 'argb'
}
