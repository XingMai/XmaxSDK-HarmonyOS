//
//  ErrorMessageFormatter.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { XmaxLogger } from '../logging/XmaxLogger';
import { XmaxError } from './XmaxError';

/** 提取平台异常中的错误码和可读信息。 */
interface PlatformError {

  /** 平台错误信息 */
  code?: number | string;
  message?: string;
}

/** 将平台异常和任意错误值整理为可读的错误说明。 */
export class ErrorMessageFormatter {
  /**
   * 从任意错误值中提取可读信息，保留可用的平台错误码。
   *
   * @param error 当前操作失败或终止的原因。
   * @returns 可展示或记录的错误文本。
   */
  static format(error: Object): string {
    if (error instanceof XmaxError) {
      const apiCode: string = error.apiCode === undefined ?
        '' : `${XmaxLogger.localized("，业务码 ", ", API Code ")}${error.apiCode}`;
      const httpStatus: string = error.httpStatus === undefined ?
        '' : `${XmaxLogger.localized('，', ', ')}HTTP ${error.httpStatus}`;

      return `${error.message}${XmaxLogger.localized('（', ' (')}${error.code}${apiCode}${httpStatus}${XmaxLogger.localized('）', ')')}`;
    }

    if (error instanceof Error && error.message.trim().length > 0) {
      return error.message.trim();
    }

    const platformError: PlatformError = error as PlatformError;
    const message: string = platformError.message?.trim() ?? '';
    const code: number | string | undefined = platformError.code;
    if (message.length > 0) {
      return code === undefined ? message : `${message}${XmaxLogger.localized("（平台错误码：", " (Platform Error Code: ")}${code}${XmaxLogger.localized('）', ')')}`;
    }
    if (code !== undefined) {
      return `${XmaxLogger.localized("平台请求失败（平台错误码：", "Platform Request Failed (Platform Error Code: ")}${code}${XmaxLogger.localized('）', ')')}`;
    }

    try {
      const serialized: string = JSON.stringify(error);
      return serialized.length > 0 && serialized !== '{}' ? serialized : String(error);
    } catch (_error) {
      return String(error);
    }
  }
}
