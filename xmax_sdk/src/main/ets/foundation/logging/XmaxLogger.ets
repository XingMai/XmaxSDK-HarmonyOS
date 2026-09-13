import { hilog } from '@kit.PerformanceAnalysisKit';
import { XmaxLoggerOption } from './XmaxLoggerOption';
import { XmaxEnvironment } from '../../core/XmaxEnvironment';

const LOG_DOMAIN: number = 0x584D;
const LOG_TAG: string = 'XmaxSDK';
const LOG_PREFIX: string = '[Xmax]';
type LogMessage = string | (() => string);

/** SDK 内部日志入口；调用方不应传入认证信息或完整敏感响应。 */
export class XmaxLogger {
  private static options: XmaxLoggerOption = XmaxLoggerOption.NONE;
  private static environment: XmaxEnvironment = XmaxEnvironment.CHINA;

  /** 配置 SDK 全局日志；新客户端的配置会覆盖之前的配置。 */
  static configure(options: XmaxLoggerOption, environment: XmaxEnvironment = XmaxEnvironment.CHINA): void {
    XmaxLogger.options = options;
    XmaxLogger.environment = environment;
  }

  /** 日志标题保留中英双语，细项跟随最后创建的 Client 的服务环境。 */
  static localized(chinese: string, english: string): string {
    return XmaxLogger.environment === XmaxEnvironment.CHINA ? chinese : english;
  }

  static isEnabled(option: XmaxLoggerOption): boolean {
    return option !== XmaxLoggerOption.NONE && (XmaxLogger.options & option) === option;
  }

  static debug(
    message: LogMessage,
    category?: string,
    option: XmaxLoggerOption = XmaxLoggerOption.BUSINESS
  ): void {
    if (!XmaxLogger.isEnabled(option)) {
      return;
    }
    hilog.debug(
      LOG_DOMAIN,
      LOG_TAG,
      '%{public}s',
      XmaxLogger.format(message, category)
    );
  }

  static info(
    message: LogMessage,
    category?: string,
    option: XmaxLoggerOption = XmaxLoggerOption.BUSINESS
  ): void {
    if (!XmaxLogger.isEnabled(option)) {
      return;
    }
    hilog.info(
      LOG_DOMAIN,
      LOG_TAG,
      '%{public}s',
      XmaxLogger.format(message, category)
    );
  }

  static warn(
    message: LogMessage,
    category?: string,
    option: XmaxLoggerOption = XmaxLoggerOption.BUSINESS
  ): void {
    if (!XmaxLogger.isEnabled(option)) {
      return;
    }
    hilog.warn(
      LOG_DOMAIN,
      LOG_TAG,
      '%{public}s',
      XmaxLogger.format(message, category)
    );
  }

  static error(
    message: LogMessage,
    category?: string,
    option: XmaxLoggerOption = XmaxLoggerOption.BUSINESS
  ): void {
    if (!XmaxLogger.isEnabled(option)) {
      return;
    }
    hilog.error(
      LOG_DOMAIN,
      LOG_TAG,
      '%{public}s',
      XmaxLogger.format(message, category)
    );
  }

  private static format(
    message: LogMessage,
    category?: string
  ): string {
    const redacted: string = XmaxLogger.redact(typeof message === 'string' ? message : message());
    const normalizedCategory: string = category?.trim() ?? '';
    const categoryPrefix: string = normalizedCategory.length === 0 ? '' : `[${normalizedCategory}]`;
    const prefix: string = `${LOG_PREFIX}${categoryPrefix}`;
    const prefixed: string = redacted.replace(
      /\n/g,
      `\n${prefix} `
    );

    return `${prefix} ${prefixed}`;
  }

  private static redact(message: string): string {
    return message
      .replace(/(authorization\s*[:=]\s*)(?:Bearer|Basic)\s+[^\s,;]+/gi, '$1[REDACTED]')
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
