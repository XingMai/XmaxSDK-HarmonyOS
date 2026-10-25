//
//  PermissionManaging.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/** An interface for checking and requesting SDK permissions. */
export interface PermissionManaging {

  /**
   * Ensures camera access is granted.
   *
   * The Promise fulfills after permission is confirmed.
   */
  ensureCameraPermission(): Promise<void>;

  /**
   * Ensures microphone access is granted.
   *
   * The Promise fulfills after permission is confirmed.
   */
  ensureMicrophonePermission(): Promise<void>;
}
