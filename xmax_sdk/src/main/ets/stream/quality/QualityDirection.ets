//
//  QualityDirection.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { RealtimeNetworkQualityLevel } from '../../service/realtime/RealtimeNetworkQuality';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import { EncodingBitratePolicy } from '../encoding/EncodingBitratePolicy';
import { QualityVideoFormat } from './QualityVideoFormat';

/** 单个传输方向的连续采样、稳定窗口及升降档规则。 */
export class QualityDirection {

  /** 传输基准与方向 */
  readonly baseline: RealtimeVideoFormat;
  private readonly downlink: boolean;

  /** 当前档位 */
  private currentLevel: number;

  /** 连续网络质量采样 */
  private goodSamples: number = 0;
  private poorSamples: number = 0;
  private lastSample: number | undefined;

  /** 稳定窗口与升档试探限制 */
  private stableUntil: number = 0;
  private upgradeAfter: number = 0;
  private probeUntil: number = 0;

  /**
   * 创建单方向自动调档状态。
   *
   * @param baseline 保持原始媒体比例与用户编码选项的视频格式基准。
   * @param level 传输档位，范围 1～5，数值越小质量越高。
   * @param downlink 是否为下行方向；false 表示上行。
   * @returns 新建的 QualityDirection 实例。
   */
  constructor(baseline: RealtimeVideoFormat, level: number, downlink: boolean) {
    this.baseline = baseline;
    this.downlink = downlink;
    this.currentLevel = Math.min(5, Math.max(1, Math.round(level)));
    while (this.currentLevel > 1 && !this.supports(this.currentLevel)) { this.currentLevel--; }
  }

  /**
   * 读取当前已提交成功的传输档位。
   *
   * @returns 1～5 的档位，数值越小质量越高。
   */
  get level(): number { return this.currentLevel; }

  /**
   * 计算当前已生效档位的传输格式。
   *
   * @returns 当前方向的传输格式。
   */
  get format(): RealtimeVideoFormat { return this.formatAt(this.currentLevel); }

  /**
   * 计算指定档位在当前方向上的传输格式。
   *
   * @param level 传输档位，范围 1～5，数值越小质量越高。
   * @returns 该档位的传输格式。
   */
  private formatAt(level: number): RealtimeVideoFormat {
    return QualityVideoFormat.resolve(this.baseline, level, this.downlink);
  }

  /**
   * 清空连续好、差网络采样和上次采样时间。
   *
   * @returns 无返回值。
   */
  resetSamples(): void {
    this.goodSamples = 0;
    this.poorSamples = 0;
    this.lastSample = undefined;
  }

  /**
   * 累计有效网络采样，在满足连续次数与稳定窗口时提出可用档位。
   *
   * @param quality 当前方向或上下行的网络质量采样。
   * @param sampledAt 网络采样的单调时间，单位秒。
   * @param now 当前单调时间，单位秒。
   * @returns 建议的新档位；样本无效、仍在稳定期或无需调整时返回 undefined。
   */
  observe(quality: RealtimeNetworkQualityLevel, sampledAt: number, now: number): number | undefined {
    if (!Number.isFinite(sampledAt) || !Number.isFinite(now) || sampledAt > now ||
      (this.lastSample !== undefined && sampledAt <= this.lastSample)) { return undefined; }
    if (this.lastSample !== undefined && sampledAt - this.lastSample > 5) { this.resetSamples(); }
    this.lastSample = sampledAt;
    if (now - sampledAt > 5 || now < this.stableUntil) {
      this.goodSamples = 0;
      this.poorSamples = 0;
      return undefined;
    }
    let step: number;
    switch (quality) {
      case RealtimeNetworkQualityLevel.BAD:
      case RealtimeNetworkQualityLevel.VERY_BAD:
        this.goodSamples = 0;
        this.poorSamples++;
        if (this.poorSamples < 3) { return undefined; }
        step = 1;
        break;
      case RealtimeNetworkQualityLevel.EXCELLENT:
      case RealtimeNetworkQualityLevel.GOOD:
        this.poorSamples = 0;
        this.goodSamples++;
        if (this.goodSamples < 5 || now < this.upgradeAfter) { return undefined; }
        step = -1;
        break;
      default:
        this.goodSamples = 0;
        this.poorSamples = 0;
        return undefined;
    }
    let candidate: number = this.currentLevel + step;
    while (candidate >= 1 && candidate <= 5) {
      if (!QualityVideoFormat.same(this.formatAt(candidate), this.format) && this.supports(candidate)) { return candidate; }
      candidate += step;
    }
    return undefined;
  }

  /**
   * 记录调档提交结果，设置稳定窗口和升档试探期，仅成功时变更当前档位。
   *
   * @param next 需要提交的新状态或档位。
   * @param success 此次配置是否已成功提交。
   * @param now 当前单调时间，单位秒。
   * @returns 无返回值。
   */
  complete(next: number, success: boolean, now: number): void {
    this.resetSamples();
    this.stableUntil = now + 4;
    if (!success) { return; }
    if (next < this.currentLevel) { this.probeUntil = now + 20; }
    else if (next > this.currentLevel) {
      if (now < this.probeUntil) { this.upgradeAfter = now + 60; }
      this.probeUntil = 0;
    }
    this.currentLevel = next;
  }

  /**
   * 检查当前方向是否支持指定档位的格式与码率。
   *
   * @param level 传输档位，范围 1～5，数值越小质量越高。
   * @returns 档位配置可提交时返回 true。
   */
  private supports(level: number): boolean {
    if (this.downlink) { return true; }
    try { EncodingBitratePolicy.resolve(this.formatAt(level)); return true; }
    catch (_error) { return false; }
  }
}
