import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import { MemoryQualityHistoryStore, QualityHistoryStore } from './QualityHistory';

/** SDK 私有 Preferences；存储不可用时本次运行仍可调档。 */
export class QualityPreferences implements QualityHistoryStore {
  private storage: preferences.Preferences | undefined;
  private readonly fallback: MemoryQualityHistoryStore = new MemoryQualityHistoryStore();
  constructor(context: common.Context) {
    try {
      this.storage = preferences.getPreferencesSync(context, { name: 'xmax_quality_history' });
    } catch (error) {
      XmaxLogger.warn('Quality history persistence unavailable: ' + String(error), 'Quality');
    }
  }
  getNumber(key: string): number | undefined {
    if (this.storage === undefined) { return this.fallback.getNumber(key); }
    const value: preferences.ValueType = this.storage.getSync(key, -1);
    return typeof value === 'number' ? value : undefined;
  }
  setNumber(key: string, value: number): void {
    if (this.storage === undefined) { this.fallback.setNumber(key, value); }
    else { this.storage.putSync(key, value); }
  }
  flush(): void {
    this.storage?.flush().catch((error: Object): void => {
      XmaxLogger.warn('Failed to flush quality history: ' + String(error), 'Quality');
    });
  }
}
