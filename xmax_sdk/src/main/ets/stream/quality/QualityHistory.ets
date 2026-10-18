import { XmaxLogger } from '../../foundation/logging/XmaxLogger';

export interface QualityHistoryStore {
  getNumber(key: string): number | undefined;
  setNumber(key: string, value: number): void;
  flush(): void;
}

export class MemoryQualityHistoryStore implements QualityHistoryStore {
  private readonly values: Map<string, number> = new Map();
  getNumber(key: string): number | undefined { return this.values.get(key); }
  setNumber(key: string, value: number): void { this.values.set(key, value); }
  flush(): void {}
}

/** 按 RTC 厂商、模型和方向隔离，仅恢复一小时内成功应用的档位。 */
export class QualityHistory {
  private readonly model: string;
  private readonly store: QualityHistoryStore;
  constructor(model: string, store: QualityHistoryStore) {
    this.model = model;
    this.store = store;
  }
  read(downlink: boolean, now: number = Date.now() / 1000): number {
    try {
      const key: string = this.key(downlink);
      const level: number | undefined = this.store.getNumber(key);
      const saved: number | undefined = this.store.getNumber(key + '.time');
      if (level !== undefined && Number.isInteger(level) && level >= 1 && level <= 5 &&
        saved !== undefined && saved > 0 && now >= saved && now - saved < 3600) {
        return level;
      }
    } catch (error) {
      XmaxLogger.warn('Failed to read quality history: ' + String(error), 'Quality');
    }
    return 2;
  }
  write(level: number, downlink: boolean, now: number = Date.now() / 1000): void {
    if (!Number.isInteger(level) || level < 1 || level > 5 || !Number.isFinite(now) || now <= 0) { return; }
    try {
      const key: string = this.key(downlink);
      this.store.setNumber(key, level);
      this.store.setNumber(key + '.time', now);
      this.store.flush();
    } catch (error) {
      XmaxLogger.warn('Failed to save quality history: ' + String(error), 'Quality');
    }
  }
  private key(downlink: boolean): string {
    return `xmax.quality.volcengine.${this.model}.${downlink ? 'downlink' : 'uplink'}`;
  }
}
