import { XmaxLogger } from '../logging/XmaxLogger';
import { XmaxError } from './XmaxError';

interface PlatformError {
  code?: number | string;
  message?: string;
}

export class ErrorMessageFormatter {
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
