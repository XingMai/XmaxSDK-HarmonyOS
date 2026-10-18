//
//  CameraPreviewReadyHandler.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/**
 * 内部摄像头预览就绪通知；接入方通过 RealtimeState.READY 监听。
 *
 * @returns 无返回值。
 */
export type CameraPreviewReadyHandler = () => void;
