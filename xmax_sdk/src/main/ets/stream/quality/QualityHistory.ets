//
//  QualityHistory.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { XmaxLogger } from '../../foundation/logging/XmaxLogger';

/** 提供调档历史使用的数值读取、写入和持久化能力。 */
export interface QualityHistoryStore {
  /**
   * 读取指定键保存的数值。
   *
   * @param key 数值存储键。
   * @returns 已保存数值；键不存在时返回 undefined。
   */
  getNumber(key: string): number | undefined;

  /**
   * 将数值写入指定存储键。
   *
   * @param key 数值存储键。
   * @param value 待校验、转换或保存的数值。
   * @returns 无返回值。
   */
  setNumber(key: string, value: number): void;

  /**
   * 提交已写入的历史数据；内存实现无需额外操作。
   *
   * @returns 无返回值。
   */
  flush(): void;
}

/** 在内存中保存调档历史，供无需跨进程保留历史的场景使用。 */
export class MemoryQualityHistoryStore implements QualityHistoryStore {

  /** 内存数值存储 */
  private readonly values: Map<string, number> = new Map();

  /**
   * 读取指定键保存的数值。
   *
   * @param key 数值存储键。
   * @returns 已保存数值；键不存在时返回 undefined。
   */
  getNumber(key: string): number | undefined { return this.values.get(key); }

  /**
   * 将数值写入指定存储键。
   *
   * @param key 数值存储键。
   * @param value 待校验、转换或保存的数值。
   * @returns 无返回值。
   */
  setNumber(key: string, value: number): void { this.values.set(key, value); }

  /**
   * 提交已写入的历史数据；内存实现无需额外操作。
   *
   * @returns 无返回值。
   */
  flush(): void {}
}

/** 按 RTC 厂商、模型和方向隔离，仅恢复一小时内成功应用的档位。 */
export class QualityHistory {

  /** 模型与历史存储命名空间 */
  private readonly model: string;
  private readonly store: QualityHistoryStore;

  /**
   * 创建模型隔离的调档历史。
   *
   * @param model 生成模型名称，用于隔离各模型的历史档位。
   * @param store 保存调档历史数值的存储实现。
   * @returns 新建的 QualityHistory 实例。
   */
  constructor(model: string, store: QualityHistoryStore) {
    this.model = model;
    this.store = store;
  }

  /**
   * 读取指定方向一小时内的有效历史档位；无有效记录时使用默认档位。
   *
   * @param downlink 是否为下行方向；false 表示上行。
   * @param now 当前 Unix 时间，单位秒；默认读取系统时间。
   * @returns 有效历史档位或默认档位 2。
   */
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

  /**
   * 保存指定方向的成功档位及其时间，并请求持久化。
   *
   * @param level 传输档位，范围 1～5，数值越小质量越高。
   * @param downlink 是否为下行方向；false 表示上行。
   * @param now 当前 Unix 时间，单位秒；默认读取系统时间。
   * @returns 无返回值。
   */
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

  /**
   * 生成按模型和传输方向隔离的历史存储键。
   *
   * @param downlink 是否为下行方向；false 表示上行。
   * @returns 当前模型和方向对应的历史键前缀。
   */
  private key(downlink: boolean): string {
    return `xmax.quality.volcengine.${this.model}.${downlink ? 'downlink' : 'uplink'}`;
  }
}
