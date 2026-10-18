//
//  RuntimeInfo.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { deviceInfo } from '@kit.BasicServicesKit';
import { XMAX_SDK_VERSION } from './SDKVersion';

export const RUNTIME_PLATFORM: string = 'harmonyos';

/** 携带房间信令所需的平台、系统版本、SDK 版本和设备型号。 */
export interface RuntimeInfoPayload {

  /** 可序列化的运行环境字段 */
  platform: string;
  os_version: string;
  sdk_version: string;
  device_model: string;
}

/** API 和房间信令共享的进程级运行环境快照。 */
export class RuntimeInfo {

  /** 运行环境缓存 */
  private static cached: RuntimeInfo | undefined;

  /** 平台与版本信息 */
  readonly platform: string = RUNTIME_PLATFORM;
  readonly osVersion: string;
  readonly sdkVersion: string = XMAX_SDK_VERSION;
  readonly deviceModel: string;

  /**
   * 创建运行环境快照。
   *
   * @returns 新建的 RuntimeInfo 实例。
   */
  private constructor() {
    this.osVersion = RuntimeInfo.readValue((): string => deviceInfo.distributionOSVersion) ||
      RuntimeInfo.readValue((): string => deviceInfo.osFullName) || 'unknown';
    this.deviceModel = RuntimeInfo.readValue((): string => deviceInfo.productModel) || 'unknown';
  }

  /**
   * 读取缓存的当前运行环境信息。
   *
   * @returns 当前设备与 SDK 的运行环境快照。
   */
  static get current(): RuntimeInfo {
    if (RuntimeInfo.cached === undefined) {
      RuntimeInfo.cached = new RuntimeInfo();
    }
    return RuntimeInfo.cached;
  }

  /**
   * 将运行环境快照转换为房间信令字段。
   *
   * @returns 用于 JSON 序列化的运行环境数据。
   */
  toPayload(): RuntimeInfoPayload {
    return {
      platform: this.platform,
      os_version: this.osVersion,
      sdk_version: this.sdkVersion,
      device_model: this.deviceModel
    };
  }

  /**
   * 设备信息不可用时仍允许正常发起 API 和信令。
   *
   * @param read 读取系统属性值的函数。
   * @returns 去除首尾空白的系统属性值；读取失败时返回空字符串。
   */
  private static readValue(read: () => string): string {
    try {
      return read().trim();
    } catch (_error) {
      return '';
    }
  }
}
