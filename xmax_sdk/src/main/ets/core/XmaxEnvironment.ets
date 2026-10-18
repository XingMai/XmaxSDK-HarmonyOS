//
//  XmaxEnvironment.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/** Xmax 服务环境。 */
export enum XmaxEnvironment {

  /** 国内环境。 */
  CHINA = 'china',

  /** 海外环境。 */
  GLOBAL = 'global'
}

/**
 * 根据服务环境返回对应的 API 基础地址。
 *
 * @param environment SDK 连接的服务环境。
 * @returns 当前服务环境使用的 API 基础地址。
 */
export function apiBaseURL(environment: XmaxEnvironment): string {
  switch (environment) {
    case XmaxEnvironment.CHINA:
      return 'https://cloud.xmax.22duck.cn/open/api/v1';
    case XmaxEnvironment.GLOBAL:
      return 'https://api.xmax.cloud/open/api/v1';
  }
}
