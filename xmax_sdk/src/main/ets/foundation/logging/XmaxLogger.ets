import { hilog } from '@kit.PerformanceAnalysisKit';

const LOG_DOMAIN: number = 0x584D;
const LOG_TAG: string = 'XmaxSDK';
const LOG_PREFIX: string = '[Xmax]';
const LOG_TRAILING_LINE: string = '\n\u200B';

export class XmaxLogger {
  static debug(
    message: string,
    category?: string
  ): void {
    hilog.debug(
      LOG_DOMAIN,
      LOG_TAG,
      '%{public}s',
      XmaxLogger.format(message, category)
    );
  }

  static info(
    message: string,
    category?: string
  ): void {
    hilog.info(
      LOG_DOMAIN,
      LOG_TAG,
      '%{public}s',
      XmaxLogger.format(message, category)
    );
  }

  static warn(
    message: string,
    category?: string
  ): void {
    hilog.warn(
      LOG_DOMAIN,
      LOG_TAG,
      '%{public}s',
      XmaxLogger.format(message, category)
    );
  }

  static error(
    message: string,
    category?: string
  ): void {
    hilog.error(
      LOG_DOMAIN,
      LOG_TAG,
      '%{public}s',
      XmaxLogger.format(message, category)
    );
  }

  private static format(
    message: string,
    category?: string
  ): string {
    const redacted: string = XmaxLogger.redact(message);
    const categoryPrefix: string = category === undefined ? '' : `[${category}]`;
    const prefix: string = `${LOG_PREFIX}${categoryPrefix}`;
    const prefixed: string = redacted.replace(
      /\n/g,
      `\n${prefix} `
    );

    return `${prefix} ${prefixed}${LOG_TRAILING_LINE}`;
  }

  private static redact(message: string): string {
    return message
      .replace(
        /("[^"]*(?:api[_-]?key|token|secret|authorization|access[_-]?key)[^"]*"\s*:\s*)("[^"]*"|[^,}\s]+)/gi,
        '$1"[REDACTED]"'
      )
      .replace(
        /((?:api[_-]?key|[a-z0-9_-]*(?:token|secret|authorization|access[_-]?key)[a-z0-9_-]*)\s*[:=]\s*)[^\s,;]+/gi,
        '$1[REDACTED]'
      );
  }
}
