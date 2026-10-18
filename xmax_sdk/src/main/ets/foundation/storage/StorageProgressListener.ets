//
//  StorageProgressListener.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/**
 * 接收已传输字节数和总字节数的进度回调。
 *
 * @param completedBytes 已传输的字节数。
 * @param totalBytes 此次传输的总字节数。
 * @returns 无返回值。
 */
export type StorageProgressListener = (completedBytes: number, totalBytes: number) => void;
