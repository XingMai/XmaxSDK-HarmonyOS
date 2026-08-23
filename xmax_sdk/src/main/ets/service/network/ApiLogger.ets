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
    if (successful) {
      XmaxLogger.debug(
        `${method} ${path} 成功\n` +
        `├─ 状态：${statusCode}\n` +
        `└─ 耗时：${durationMs} ms`,
        'API'
      );
      return;
    }

    const formattedBody: string = ApiLogger.formatBody(body);
    const message: string =
      `${method} ${path}\n` +
      `├─ 状态：${statusCode}\n` +
      `├─ 耗时：${durationMs} ms\n` +
      `└─ 数据：\n` +
      `   ${formattedBody}`;

    XmaxLogger.error(message, 'API');
  }

  static logFailure(
    method: string,
    path: string,
    error: Object,
    durationMs: number
  ): void {
    XmaxLogger.error(
      `${method} ${path} 失败\n` +
      `├─ 耗时：${durationMs} ms\n` +
      `└─ 原因：${ErrorMessageFormatter.format(error)}`,
      'API'
    );
  }

  private static formatBody(body?: string): string {
    if (body === undefined || body.trim().length === 0) {
      return '无';
    }

    try {
      const value: Object = JSON.parse(body) as Object;
      return JSON.stringify(value, null, 2).replace(/\n/g, '\n   ');
    } catch (_error) {
      return body;
    }
  }
}
