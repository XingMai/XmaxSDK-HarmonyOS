//
//  ImageManaging.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { image } from '@kit.ImageKit';
import { DecodedImage } from './DecodedImage';

/** An interface for platform image processing. */
export interface ImageManaging {

  /**
   * Decodes encoded image data.
   *
   * @param data The complete encoded image bytes.
   *
   * @returns The decoded image owned by XmaxSDK.
   */
  decode(
    data: ArrayBuffer | Uint8Array
  ): Promise<DecodedImage>;

  /**
   * Decodes a local image file.
   *
   * @param filePath The readable local image file path.
   *
   * @returns The decoded image owned by XmaxSDK.
   */
  decodeFile(
    filePath: string
  ): Promise<DecodedImage>;

  /**
   * Snapshots a PixelMap without changing caller ownership.
   *
   * @param pixelMap The caller-owned PixelMap, which XmaxSDK neither modifies nor releases.
   *
   * @returns The decoded image owned by XmaxSDK.
   */
  decodePixelMap(
    pixelMap: image.PixelMap
  ): Promise<DecodedImage>;
}
