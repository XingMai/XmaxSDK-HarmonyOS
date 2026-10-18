//
//  ApiLogger.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { XmaxLoggerOption } from '../../foundation/logging/XmaxLoggerOption';
import { ErrorMessageFormatter } from '../../foundation/errors/ErrorMessageFormatter';
import { XmaxLogger } from '../../foundation/logging/XmaxLogger';

/** 输出请求结果、失败原因和耗时；由统一日志层完成敏感字段脱敏。 */
export class ApiLogger {
  /**
   * 按请求结果输出状态码、响应内容和耗时。
   *
   * @param method HTTP 请求方法。
   * @param path HTTP 请求路径。
   * @param statusCode HTTP 响应状态码。
   * @param body HTTP 响应正文。
   * @param durationMs 请求耗时，单位毫秒。
   * @param successful 请求是否已按业务规则成功完成。
   * @returns 无返回值。
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
      XmaxLogger.localized("└─ 数据：\n", "└─ Data: \n") +
      `   ${formattedBody}`;

    XmaxLogger.error(message, 'API');
  }

  /**
   * 输出网络请求失败原因与耗时。
   *
   * @param method HTTP 请求方法。
   * @param path HTTP 请求路径。
   * @param error 当前操作失败或终止的原因。
   * @param durationMs 请求耗时，单位毫秒。
   * @returns 无返回值。
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
   * 将响应体整理为适合日志查看的文本。
   *
   * @param body HTTP 响应正文。
   * @returns 格式化的响应体；缺失时使用空响应说明。
   */
  private static formatBody(body?: string): string {
    if (body === undefined || body.trim().length === 0) {
      return XmaxLogger.localized("无", "None");
    }

    try {
      const value: Object = JSON.parse(body) as Object;
      return JSON.stringify(value, null, 2).replace(/\n/g, '\n   ');
    } catch (_error) {
      return body;
    }
  }
}
