//
//  XmaxEnvironment.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/** An Xmax service environment. */
export enum XmaxEnvironment {

  /** The China environment. */
  CHINA = 'china',

  /** The global environment. */
  GLOBAL = 'global'
}

/**
 * Returns the API base URL for a service environment.
 *
 * @param environment The service environment.
 *
 * @returns The environment's API base URL.
 */
export function apiBaseURL(
  environment: XmaxEnvironment
): string {
  switch (environment) {
    case XmaxEnvironment.CHINA:
      return 'https://cloud.xmax.22duck.cn/open/api/v1';
    case XmaxEnvironment.GLOBAL:
      return 'https://api.xmax.cloud/open/api/v1';
  }
}
