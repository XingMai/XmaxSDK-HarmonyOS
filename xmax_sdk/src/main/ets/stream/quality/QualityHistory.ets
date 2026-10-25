//
//  QualityHistory.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { XmaxLogger } from '../../foundation/logging/XmaxLogger';

/** A numeric store for reading, writing, and persisting quality history. */
export interface QualityHistoryStore {

  /**
   * Returns a stored numeric value.
   *
   * @param key The numeric history storage key.
   *
   * @returns The stored value, or undefined if the key is absent.
   */
  getNumber(
    key: string
  ): number | undefined;

  /**
   * Stores a numeric value under a key.
   *
   * @param key The numeric history storage key.
   * @param value The numeric quality history value to store.
   */
  setNumber(
    key: string,
    value: number
  ): void;

  /** Persists pending history; memory stores require no additional work. */
  flush(): void;
}

/** An in-memory quality history store without cross-process persistence. */
export class MemoryQualityHistoryStore implements QualityHistoryStore {

  /** The numeric values retained by the in-memory history store. */
  private readonly values: Map<string, number> = new Map();

  /**
   * Returns a stored numeric value.
   *
   * @param key The numeric history storage key.
   *
   * @returns The stored value, or undefined if the key is absent.
   */
  getNumber(
    key: string
  ): number | undefined {
    return this.values.get(key);
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
    this.values.set(
      key,
      value
    );
  }

  /** Persists pending history; memory stores require no additional work. */
  flush(): void { }
}

/** Restores successful levels from the last hour, isolated by RTC vendor, model, and direction. */
export class QualityHistory {

  /** The model name used to isolate stored quality history. */
  private readonly model: string;

  /** The numeric store backing quality history. */
  private readonly store: QualityHistoryStore;

  /** Creates model-specific quality history. */
  constructor(
    model: string,
    store: QualityHistoryStore
  ) {
    this.model = model;
    this.store = store;
  }

  /**
   * Returns a valid level from the last hour or the default level.
   *
   * @param downlink Whether this is downlink; false selects uplink.
   * @param now The current Unix time, in seconds; defaults to system time.
   *
   * @returns The valid historical level, or default level 2.
   */
  read(
    downlink: boolean,
    now: number = Date.now() / 1000
  ): number {
    try {
      const key: string = this.key(downlink);
      const level: number | undefined = this.store.getNumber(key);
      const saved: number | undefined = this.store.getNumber(key + '.time');
      if (level !== undefined && Number.isInteger(level) && level >= 1 && level <= 5 &&
        saved !== undefined && saved > 0 && now >= saved && now - saved < 3600) {
        return level;
      }
    } catch (error) {
      XmaxLogger.warn(
        'Failed to read quality history: ' + String(error),
        'Quality'
      );
    }

    return 2;
  }

  /**
   * Stores a successful level and timestamp and requests persistence.
   *
   * @param level The quality level, from 1 to 5; lower values mean higher quality.
   * @param downlink Whether this is downlink; false selects uplink.
   * @param now The current Unix time, in seconds; defaults to system time.
   */
  write(
    level: number,
    downlink: boolean,
    now: number = Date.now() / 1000
  ): void {
    if (!Number.isInteger(level) || level < 1 || level > 5 || !Number.isFinite(now) || now <= 0) { return; }

    try {
      const key: string = this.key(downlink);
      this.store.setNumber(
        key,
        level
      );
      this.store.setNumber(
        key + '.time',
        now
      );
      this.store.flush();
    } catch (error) {
      XmaxLogger.warn(
        'Failed to save quality history: ' + String(error),
        'Quality'
      );
    }
  }

  /**
   * Creates a history key isolated by model and direction.
   *
   * @param downlink Whether this is downlink; false selects uplink.
   *
   * @returns The current model and direction's history key prefix.
   */
  private key(
    downlink: boolean
  ): string {
    return `xmax.quality.volcengine.${this.model}.${downlink ? 'downlink' : 'uplink'}`;
  }
}
