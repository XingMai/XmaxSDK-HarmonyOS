//
//  StorageProgressListener.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/**
 * Receives transferred and total byte counts.
 *
 * @param completedBytes The number of transferred bytes.
 * @param totalBytes The total transfer byte count.
 */
export type StorageProgressListener = (
  completedBytes: number,
  totalBytes: number
) => void;
