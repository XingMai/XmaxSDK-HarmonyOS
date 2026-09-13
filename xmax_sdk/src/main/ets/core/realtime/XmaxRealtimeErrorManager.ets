import {
  XmaxError
} from '../../foundation/errors/XmaxError';
import { XmaxLogger } from '../../foundation/logging/XmaxLogger';

/** 统一记录实时错误；生命周期失败通过 RealtimeState.reason 通知接入方。 */
export class XmaxRealtimeErrorManager {

  // 同一个错误沿调用栈被多层捕获时，只记录和通知一次。
  private readonly reportedErrors: WeakSet<XmaxError> = new WeakSet();

  /** 同一个错误只记录一次，并保留原始对象。 */
  handle(error: XmaxError): XmaxError {
    if (this.reportedErrors.has(error)) {
      return error;
    }

    this.reportedErrors.add(error);
    XmaxLogger.error((): string => this.format(error), 'Realtime');

    return error;
  }

  private format(error: XmaxError): string {
    const details: string[] = [
      `错误码：${error.code}`,
      `级别：${error.severity}`,
      `信息：${error.message}`
    ];

    if (error.apiCode !== undefined) {
      details.push(`业务码：${error.apiCode}`);
    }
    if (error.httpStatus !== undefined) {
      details.push(`HTTP 状态：${error.httpStatus}`);
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
