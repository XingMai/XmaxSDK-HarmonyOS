//
//  QualityConfiguration.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import { RealtimeNetworkQuality } from '../../service/realtime/RealtimeNetworkQuality';
import { QualityVideoFormat } from './QualityVideoFormat';

/**
 * 接收带单调采样时间的网络质量事件，供生成流程安排自动调档。
 *
 * @param quality 当前方向或上下行的网络质量采样。
 * @param sampledAt 网络采样的单调时间，单位秒。
 * @returns 无返回值。
 */
export type AdaptiveQualityListener = (quality: RealtimeNetworkQuality, sampledAt: number) => void;

/** 保存固定媒体基准和上下行档位，并计算各方向的传输格式。 */
export class QualityConfiguration {

  /** 固定媒体与编码基准 */
  readonly baseline: RealtimeVideoFormat;

  /** 上下行传输档位 */
  readonly uplinkLevel: number;
  readonly downlinkLevel: number;

  /**
   * 创建上下行传输档位配置。
   *
   * @param baseline 保持原始媒体比例与用户编码选项的视频格式基准。
   * @param uplinkLevel 上行传输档位，1～5，数值越小质量越高。
   * @param downlinkLevel 下行传输档位，1～5，数值越小质量越高。
   * @returns 新建的 QualityConfiguration 实例。
   */
  constructor(baseline: RealtimeVideoFormat, uplinkLevel: number, downlinkLevel: number) {
    this.baseline = baseline;
    this.uplinkLevel = uplinkLevel;
    this.downlinkLevel = downlinkLevel;
  }

  /**
   * 计算当前上行档位对应的传输格式。
   *
   * @returns 保留显式码率与编码偏好的上行格式。
   */
  get uplink(): RealtimeVideoFormat { return QualityVideoFormat.resolve(this.baseline, this.uplinkLevel, false); }

  /**
   * 计算当前下行档位对应的传输格式。
   *
   * @returns 用于结果流尺寸与码率预算的下行格式。
   */
  get downlink(): RealtimeVideoFormat { return QualityVideoFormat.resolve(this.baseline, this.downlinkLevel, true); }
}

/** 分别给出上下行建议档位；未设置的方向保持当前档位。 */
export class QualityChange {

  /** 上下行候选档位 */
  readonly uplink?: number;
  readonly downlink?: number;

  /**
   * 创建上下行调档建议。
   *
   * @param uplink 本地上行网络等级或建议档位。
   * @param downlink 本地下行的网络质量等级或建议档位。
   * @returns 新建的 QualityChange 实例。
   */
  constructor(uplink?: number, downlink?: number) {
    this.uplink = uplink;
    this.downlink = downlink;
  }
}
