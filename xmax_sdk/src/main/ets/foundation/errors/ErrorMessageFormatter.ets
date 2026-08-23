import { XmaxError } from './XmaxError';

interface PlatformError {
  code?: number | string;
  message?: string;
}

export class ErrorMessageFormatter {
  static format(error: Object): string {
    if (error instanceof XmaxError) {
      const apiCode: string = error.apiCode === undefined ?
        '' : `，业务码 ${error.apiCode}`;
      const httpStatus: string = error.httpStatus === undefined ?
        '' : `，HTTP ${error.httpStatus}`;

      return `${error.message}（${error.code}${apiCode}${httpStatus}）`;
    }

    if (error instanceof Error && error.message.trim().length > 0) {
      return error.message.trim();
    }

    const platformError: PlatformError = error as PlatformError;
    const message: string = platformError.message?.trim() ?? '';
    const code: number | string | undefined = platformError.code;
    if (message.length > 0) {
      return code === undefined ? message : `${message}（平台错误码：${code}）`;
    }
    if (code !== undefined) {
      return `平台请求失败（平台错误码：${code}）`;
    }

    try {
      const serialized: string = JSON.stringify(error);
      return serialized.length > 0 && serialized !== '{}' ? serialized : String(error);
    } catch (_error) {
      return String(error);
    }
  }
}
