//
//  StateTargetResolver.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { UIUtils } from '@kit.ArkUI';

/**
 * 将 ArkUI 状态代理还原为原始对象；普通对象保持不变。
 *
 * @param value 待校验、转换或保存的数值。
 * @returns 解除状态代理包装后的原始对象。
 */
export function resolveStateTarget<T extends object>(value: T): T {
  return UIUtils.getTarget(value);
}
