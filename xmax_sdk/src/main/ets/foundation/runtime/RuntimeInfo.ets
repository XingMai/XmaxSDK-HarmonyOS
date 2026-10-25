//
//  RuntimeInfo.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { deviceInfo } from '@kit.BasicServicesKit';
import { XMAX_SDK_VERSION } from './SDKVersion';

export const RUNTIME_PLATFORM: string = 'harmonyos';

/** Platform, system, SDK, and device fields used in room signaling. */
export interface RuntimeInfoPayload {

  /** The runtime platform identifier sent to the service. */
  platform: string;

  /** The system version sent in runtime metadata. */
  os_version: string;

  /** The SDK version sent in runtime metadata. */
  sdk_version: string;

  /** The device model sent in runtime metadata. */
  device_model: string;
}

/** A process-level runtime snapshot shared by API requests and room signals. */
export class RuntimeInfo {

  /** The process-level cached runtime snapshot. */
  private static cached: RuntimeInfo | undefined;

  /** The runtime platform identifier sent to the service. */
  readonly platform: string = RUNTIME_PLATFORM;

  /** The device system version. */
  readonly osVersion: string;

  /** The SDK version. */
  readonly sdkVersion: string = XMAX_SDK_VERSION;

  /** The device model. */
  readonly deviceModel: string;

  /** Creates a runtime snapshot. */
  private constructor() {
    this.osVersion = RuntimeInfo.readValue((): string => deviceInfo.distributionOSVersion) ||
      RuntimeInfo.readValue((): string => deviceInfo.osFullName) || 'unknown';
    this.deviceModel = RuntimeInfo.readValue((): string => deviceInfo.productModel) || 'unknown';
  }

  /** The cached device and SDK runtime snapshot. */
  static get current(): RuntimeInfo {
    if (RuntimeInfo.cached === undefined) {
      RuntimeInfo.cached = new RuntimeInfo();
    }
    return RuntimeInfo.cached;
  }

  /**
   * Converts runtime information into room signal fields.
   *
   * @returns The runtime data for JSON serialization.
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
   * Unavailable device information must not prevent API requests or signaling.
   *
   * @param read The system property reader.
   *
   * @returns The trimmed property value, or an empty string if reading fails.
   */
  private static readValue(
    read: () => string
  ): string {
    try {
      return read().trim();
    } catch (_error) {
      return '';
    }
  }
}
