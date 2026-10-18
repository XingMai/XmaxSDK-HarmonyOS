//
//  QualityPreferences.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import { MemoryQualityHistoryStore, QualityHistoryStore } from './QualityHistory';

/** SDK 私有 Preferences；存储不可用时本次运行仍可调档。 */
export class QualityPreferences implements QualityHistoryStore {

  /** 平台持久化存储 */
  private storage: preferences.Preferences | undefined;

  /** 存储不可用时的内存回退 */
  private readonly fallback: MemoryQualityHistoryStore = new MemoryQualityHistoryStore();

  /**
   * 创建权限 Manager。
   *
   * @param context 用于检查和申请权限的页面上下文。
   * @returns 新建的 QualityPreferences 实例。
   */
  constructor(context: common.Context) {
    try {
      this.storage = preferences.getPreferencesSync(context, { name: 'xmax_quality_history' });
    } catch (error) {
      XmaxLogger.warn('Quality history persistence unavailable: ' + String(error), 'Quality');
    }
  }

  /**
   * 读取指定键保存的数值。
   *
   * @param key 数值存储键。
   * @returns 已保存数值；键不存在时返回 undefined。
   */
  getNumber(key: string): number | undefined {
    if (this.storage === undefined) { return this.fallback.getNumber(key); }
    const value: preferences.ValueType = this.storage.getSync(key, -1);
    return typeof value === 'number' ? value : undefined;
  }

  /**
   * 将数值写入指定存储键。
   *
   * @param key 数值存储键。
   * @param value 待校验、转换或保存的数值。
   * @returns 无返回值。
   */
  setNumber(key: string, value: number): void {
    if (this.storage === undefined) { this.fallback.setNumber(key, value); }
    else { this.storage.putSync(key, value); }
  }

  /**
   * 请求将调档历史写入平台持久化存储。
   *
   * @returns 无返回值。
   */
  flush(): void {
    this.storage?.flush().catch((error: Object): void => {
      XmaxLogger.warn('Failed to flush quality history: ' + String(error), 'Quality');
    });
  }
}
