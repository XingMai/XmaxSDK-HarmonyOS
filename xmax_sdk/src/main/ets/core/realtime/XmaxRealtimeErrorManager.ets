import {
  XmaxError,
  XmaxErrorCode
} from '../../foundation/errors/XmaxError';
import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import { RealtimeErrorListener } from '../../service/realtime/RealtimeError';

/** 统一记录实时错误并通过旁路监听器通知接入方。 */
export class XmaxRealtimeErrorManager {

  // 错误监听器
  private listener: RealtimeErrorListener | null = null;

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
   * 记录错误并通知监听器；正常取消仅原样返回。
   *
   * @param error 需要处理的 SDK 错误。
   * @returns 传入的错误，供原有 Promise 流程继续抛出。
   */
  handle(error: XmaxError): XmaxError {
    if (error.code === XmaxErrorCode.CANCELLED) {
      return error;
    }

    XmaxLogger.error(
      this.format(error),
      'Error'
    );
    this.notifyListener(error);

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
      `原因：${error.message}`
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

    return [`SDK 抛出错误：${error.code}`, ...formattedDetails].join('\n');
  }
}
