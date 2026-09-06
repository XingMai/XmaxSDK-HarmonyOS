import { deviceInfo } from '@kit.BasicServicesKit';
import { XMAX_SDK_VERSION } from './SDKVersion';

export const RUNTIME_PLATFORM: string = 'harmonyos';

/** 房间信令中的运行环境字段，与 iOS 使用相同的 JSON 键。 */
export interface RuntimeInfoPayload {
  platform: string;
  os_version: string;
  sdk_version: string;
  device_model: string;
}

/** API 和房间信令共享的进程级运行环境快照。 */
export class RuntimeInfo {
  private static cached: RuntimeInfo | undefined;

  readonly platform: string = RUNTIME_PLATFORM;
  readonly osVersion: string;
  readonly sdkVersion: string = XMAX_SDK_VERSION;
  readonly deviceModel: string;

  private constructor() {
    this.osVersion = RuntimeInfo.readValue((): string => deviceInfo.distributionOSVersion) ||
      RuntimeInfo.readValue((): string => deviceInfo.osFullName) || 'unknown';
    this.deviceModel = RuntimeInfo.readValue((): string => deviceInfo.productModel) || 'unknown';
  }

  static get current(): RuntimeInfo {
    if (RuntimeInfo.cached === undefined) {
      RuntimeInfo.cached = new RuntimeInfo();
    }
    return RuntimeInfo.cached;
  }

  toPayload(): RuntimeInfoPayload {
    return {
      platform: this.platform,
      os_version: this.osVersion,
      sdk_version: this.sdkVersion,
      device_model: this.deviceModel
    };
  }

  /** 设备信息不可用时仍允许正常发起 API 和信令。 */
  private static readValue(read: () => string): string {
    try {
      return read().trim();
    } catch (_error) {
      return '';
    }
  }
}
