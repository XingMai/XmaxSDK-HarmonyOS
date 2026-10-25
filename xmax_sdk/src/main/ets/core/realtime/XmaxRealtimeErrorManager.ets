//
//  XmaxRealtimeErrorManager.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import {
  XmaxError
} from '../../foundation/errors/XmaxError';
import { XmaxLogger } from '../../foundation/logging/XmaxLogger';

/**
 * Normalizes realtime error logging; lifecycle failures reach your app through
 * RealtimeState.reason.
 */
export class XmaxRealtimeErrorManager {

  /** The error identities already logged during this manager's lifetime. */
  private readonly reportedErrors: WeakSet<XmaxError> = new WeakSet();

  /**
   * Logs each error once while preserving its original identity.
   *
   * @param error The SDK error to log once and return unchanged.
   *
   * @returns The SDK error with its code and readable reason.
   */
  handle(
    error: XmaxError
  ): XmaxError {
    if (this.reportedErrors.has(error)) {
      return error;
    }

    this.reportedErrors.add(error);
    XmaxLogger.error(
      (): string => this.format(error),
      'Realtime'
    );

    return error;
  }

  /**
   * Normalizes an exception into a readable SDK error.
   *
   * @param error The SDK error whose code and details are formatted.
   *
   * @returns The SDK error for your app.
   */
  private format(
    error: XmaxError
  ): string {
    const details: string[] = [
      `${XmaxLogger.localized("错误码：", "Error Code: ")}${error.code}`,
      `${XmaxLogger.localized("信息：", "Message: ")}${error.message}`
    ];

    if (error.apiCode !== undefined) {
      details.push(`${XmaxLogger.localized("业务码：", "API Code: ")}${error.apiCode}`);
    }
    if (error.httpStatus !== undefined) {
      details.push(`${XmaxLogger.localized("HTTP 状态：", "HTTP Status: ")}${error.httpStatus}`);
    }

    const formattedDetails: string[] = details.map((
      detail: string,
      index: number
    ): string => {
      const branch: string = index === details.length - 1 ? '└─' : '├─';
      return `${branch} ${detail}`;
    });

    return ['实时服务错误 (Realtime Service Error)', ...formattedDetails].join('\n');
  }
}
