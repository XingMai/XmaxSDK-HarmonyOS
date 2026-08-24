import { UIUtils } from '@kit.ArkUI';

/** 将 ArkUI 状态代理还原为原始对象；普通对象保持不变。 */
export function resolveStateTarget<T extends object>(value: T): T {
  return UIUtils.getTarget(value);
}
