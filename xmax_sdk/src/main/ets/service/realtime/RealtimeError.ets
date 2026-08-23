import { XmaxError } from '../../foundation/errors/XmaxError';

/**
 * 实时运行错误监听器。
 *
 * @param error SDK 抛出的实时运行错误。
 */
export type RealtimeErrorListener = (error: XmaxError) => void;
