//
//  XmaxRealtimeErrorManager.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import {
  XmaxError
} from '../../foundation/errors/XmaxError';
import { XmaxLogger } from '../../foundation/logging/XmaxLogger';

/** 统一记录实时错误；生命周期失败通过 RealtimeState.reason 通知接入方。 */
export class XmaxRealtimeErrorManager {

  /** 已通知错误的去重记录 */
  private readonly reportedErrors: WeakSet<XmaxError> = new WeakSet();

  /**
   * 同一个错误只记录一次，并保留原始对象。
   *
   * @param error 当前操作失败或终止的原因。
   * @returns 包含错误码和可读原因的 SDK 错误。
   */
  handle(error: XmaxError): XmaxError {
    if (this.reportedErrors.has(error)) {
      return error;
    }

    this.reportedErrors.add(error);
    XmaxLogger.error((): string => this.format(error), 'Realtime');

    return error;
  }

  /**
   * 统一转换异常并生成可读错误信息。
   *
   * @param error 当前操作失败或终止的原因。
   * @returns 用于通知接入方的 SDK 错误。
   */
  private format(error: XmaxError): string {
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
