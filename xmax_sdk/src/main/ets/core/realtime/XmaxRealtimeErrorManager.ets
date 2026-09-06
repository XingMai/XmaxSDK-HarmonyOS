import {
  XmaxError,
  XmaxErrorSeverity
} from '../../foundation/errors/XmaxError';
import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import { RealtimeErrorListener } from '../../service/realtime/RealtimeError';

/** 统一记录实时错误，只将致命错误通知接入方。 */
export class XmaxRealtimeErrorManager {

  // 错误监听器
  private listener: RealtimeErrorListener | null = null;
  // 同一个错误沿调用栈被多层捕获时，只记录和通知一次。
  private readonly reportedErrors: WeakSet<XmaxError> = new WeakSet();

  /**
   * 设置实时错误监听器。
   *
   * @param listener 错误监听器；传入空值时清除监听器。
   * @returns 无返回值。
   */
  setListener(listener: RealtimeErrorListener | null): void {
    this.listener = listener;
  }

  /**
   * 记录各级错误；仅致命错误通知监听器。
   *
   * @param error 需要处理的 SDK 错误。
   * @returns 传入的错误，供原有 Promise 流程继续抛出。
   */
  handle(error: XmaxError): XmaxError {
    if (this.reportedErrors.has(error)) {
      return error;
    }

    this.reportedErrors.add(error);
    XmaxLogger.error((): string => this.format(error), 'Realtime');
    if (error.severity === XmaxErrorSeverity.FATAL) {
      this.notifyListener(error);
    }

    return error;
  }

  /**
   * 安全调用当前错误监听器。
   *
   * @param error 需要通知给接入方的 SDK 错误。
   * @returns 无返回值。
   */
  private notifyListener(error: XmaxError): void {
    const listener: RealtimeErrorListener | null = this.listener;
    if (listener === null) {
      return;
    }

    try {
      listener(error);
    } catch (listenerError) {
      const reason: string = listenerError instanceof Error ?
        listenerError.message : String(listenerError);
      XmaxLogger.error(
        `错误监听器执行失败\n└─ 原因：${reason}`,
        'Error'
      );
    }
  }

  /**
   * 将 SDK 错误整理为统一的多行日志内容。
   *
   * @param error 需要格式化的 SDK 错误。
   * @returns 包含错误码、原因和可选服务端信息的日志文本。
   */
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
