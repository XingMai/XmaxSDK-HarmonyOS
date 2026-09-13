import { XmaxLoggerOption } from '../../foundation/logging/XmaxLoggerOption';
import { ErrorMessageFormatter } from '../../foundation/errors/ErrorMessageFormatter';
import { XmaxLogger } from '../../foundation/logging/XmaxLogger';

export class ApiLogger {
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
