//
//  QualityPreferences.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import { MemoryQualityHistoryStore, QualityHistoryStore } from './QualityHistory';

/** SDK-private Preferences with in-memory fallback when unavailable. */
export class QualityPreferences implements QualityHistoryStore {

  /** The SDK-private platform Preferences store. */
  private storage: preferences.Preferences | undefined;

  /** The in-memory history used when platform storage is unavailable. */
  private readonly fallback: MemoryQualityHistoryStore = new MemoryQualityHistoryStore();

  /**
   * Opens persistent quality history, falling back to memory if storage is unavailable.
   *
   * @param context The application context used to open the SDK's Preferences store.
   */
  constructor(
    context: common.Context
  ) {
    try {
      this.storage = preferences.getPreferencesSync(
        context,
        { name: 'xmax_quality_history' }
      );
    } catch (error) {
      XmaxLogger.warn(
        'Quality history persistence unavailable: ' + String(error),
        'Quality'
      );
    }
  }

  /**
   * Returns a stored numeric value.
   *
   * @param key The numeric history storage key.
   *
   * @returns The stored number, -1 for an absent persistent key, or undefined for a nonnumeric
   * stored value. The in-memory fallback returns undefined for absent keys.
   */
  getNumber(
    key: string
  ): number | undefined {
    if (this.storage === undefined) { return this.fallback.getNumber(key); }
    const value: preferences.ValueType = this.storage.getSync(
      key,
      -1
    );
    return typeof value === 'number' ? value : undefined;
  }

  /**
   * Stores a numeric value under a key.
   *
   * @param key The numeric history storage key.
   * @param value The numeric quality history value to store.
   */
  setNumber(
    key: string,
    value: number
  ): void {
    if (this.storage === undefined) {
      this.fallback.setNumber(
        key,
        value
      );
    }
    else {
      this.storage.putSync(
        key,
        value
      );
    }
  }

  /** Requests platform persistence of quality history. */
  flush(): void {
    this.storage?.flush().catch((error: Object): void => {
      XmaxLogger.warn(
        'Failed to flush quality history: ' + String(error),
        'Quality'
      );
    });
  }
}
