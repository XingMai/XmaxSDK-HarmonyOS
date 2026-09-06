import { XmaxError } from '../../foundation/errors/XmaxError';

/**
 * 当前实时流程无法继续时触发的致命错误监听器。
 *
 * @param error 级别为 FATAL 的实时错误；可恢复错误由具体调用的 Promise 返回。
 */
export type RealtimeErrorListener = (error: XmaxError) => void;
