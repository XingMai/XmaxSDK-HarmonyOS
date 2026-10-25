//
//  ApiLogger.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { XmaxLoggerOption } from '../../foundation/logging/XmaxLoggerOption';
import { ErrorMessageFormatter } from '../../foundation/errors/ErrorMessageFormatter';
import { XmaxLogger } from '../../foundation/logging/XmaxLogger';

/** Logs request results, failures, and durations through the shared redaction layer. */
export class ApiLogger {

  /**
   * Logs status, response content, and request duration.
   *
   * @param method The HTTP method.
   * @param path The HTTP request path.
   * @param statusCode The HTTP response status code.
   * @param body The HTTP response body.
   * @param durationMs The request duration, in milliseconds.
   * @param successful Whether the request succeeded under business rules.
   */
  static logResponse(
    method: string,
    path: string,
    statusCode: number,
    body: string,
    durationMs: number,
    successful: boolean
  ): void {
    if (!XmaxLogger.isEnabled(XmaxLoggerOption.BUSINESS)) {
      return;
    }
    if (successful) {
      XmaxLogger.debug(
        `${method} ${path}${XmaxLogger.localized(" 成功\n", " Succeeded\n")}` +
        `${XmaxLogger.localized("├─ 状态：", "├─ Status: ")}${statusCode}\n` +
        `${XmaxLogger.localized("└─ 耗时：", "└─ Duration: ")}${durationMs} ms`,
        'API'
      );
      return;
    }

    const formattedBody: string = ApiLogger.formatBody(body);
    const message: string =
      `${method} ${path}\n` +
      `${XmaxLogger.localized("├─ 状态：", "├─ Status: ")}${statusCode}\n` +
      `${XmaxLogger.localized("├─ 耗时：", "├─ Duration: ")}${durationMs} ms\n` +
      XmaxLogger.localized(
        "└─ 数据：\n",
        "└─ Data: \n"
      ) +
      `   ${formattedBody}`;

    XmaxLogger.error(
      message,
      'API'
    );
  }

  /**
   * Logs a network failure and request duration.
   *
   * @param method The HTTP method.
   * @param path The HTTP request path.
   * @param error The request or response processing failure to log.
   * @param durationMs The request duration, in milliseconds.
   */
  static logFailure(
    method: string,
    path: string,
    error: Object,
    durationMs: number
  ): void {
    if (!XmaxLogger.isEnabled(XmaxLoggerOption.BUSINESS)) {
      return;
    }
    XmaxLogger.error(
      `${method} ${path}${XmaxLogger.localized(" 失败\n", " Failed\n")}` +
      `${XmaxLogger.localized("├─ 耗时：", "├─ Duration: ")}${durationMs} ms\n` +
      `${XmaxLogger.localized("└─ 原因：", "└─ Reason: ")}${ErrorMessageFormatter.format(error)}`,
      'API'
    );
  }

  /**
   * Formats the response body for logging.
   *
   * @param body The HTTP response body.
   *
   * @returns The formatted body, or an empty-response description if absent.
   */
  private static formatBody(
    body?: string
  ): string {
    if (body === undefined || body.trim().length === 0) {
      return XmaxLogger.localized(
        "无",
        "None"
      );
    }

    try {
      const value: Object = JSON.parse(body) as Object;
      return JSON.stringify(
        value,
        null,
        2
      ).replace(
        /\n/g,
        '\n   '
      );
    } catch (_error) {
      return body;
    }
  }
}
