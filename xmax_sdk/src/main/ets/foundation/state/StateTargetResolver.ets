//
//  StateTargetResolver.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { UIUtils } from '@kit.ArkUI';

/**
 * Unwraps an ArkUI state proxy, preserving ordinary objects.
 *
 * @param value The object or ArkUI state proxy to unwrap.
 *
 * @returns The underlying object without its state proxy.
 */
export function resolveStateTarget<T extends object>(
  value: T
): T {
  return UIUtils.getTarget(value);
}
