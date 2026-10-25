//
//  XmaxLogger.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { hilog } from '@kit.PerformanceAnalysisKit';
import { XmaxLoggerOption } from './XmaxLoggerOption';
import { XmaxEnvironment } from '../../core/XmaxEnvironment';

const LOG_DOMAIN: number = 0x584D;
const LOG_TAG: string = 'XmaxSDK';
const LOG_PREFIX: string = '[Xmax]';

/** Log text or a lazy text provider, evaluated only for enabled categories. */
type LogMessage = string | (() => string);

/** The SDK logging entry point. Callers must not supply credentials or complete sensitive responses. */
export class XmaxLogger {

  /** The realtime model and business configuration. */
  private static options: XmaxLoggerOption = XmaxLoggerOption.NONE;

  /** The environment selecting localized log details. */
  private static environment: XmaxEnvironment = XmaxEnvironment.CHINA;

  /**
   * Configures global SDK logs; the newest client replaces prior settings.
   *
   * @param options The component initialization options.
   * @param environment The service environment.
   */
  static configure(
    options: XmaxLoggerOption,
    environment: XmaxEnvironment = XmaxEnvironment.CHINA
  ): void {
    XmaxLogger.options = options;
    XmaxLogger.environment = environment;
  }

  /**
   * Keep bilingual titles; details use the latest client's environment language.
   *
   * @param chinese The text for the China environment.
   * @param english The text for other environments.
   *
   * @returns Chinese text for China; English text otherwise.
   */
  static localized(
    chinese: string,
    english: string
  ): string {
    return XmaxLogger.environment === XmaxEnvironment.CHINA ? chinese : english;
  }

  /**
   * Returns whether a log category is enabled.
   *
   * @param option The log category controlling output.
   *
   * @returns True if the category matches the current log configuration.
   */
  static isEnabled(
    option: XmaxLoggerOption
  ): boolean {
    return option !== XmaxLoggerOption.NONE && (XmaxLogger.options & option) === option;
  }

  /**
   * Writes a debug log, skipping lazy text construction for disabled categories.
   *
   * @param message The log text or lazy text provider.
   * @param category The optional log category.
   * @param option The log category controlling output.
   */
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
      XmaxLogger.format(
        message,
        category
      )
    );
  }

  /**
   * Writes an informational log, skipping lazy text construction for disabled categories.
   *
   * @param message The log text or lazy text provider.
   * @param category The optional log category.
   * @param option The log category controlling output.
   */
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
      XmaxLogger.format(
        message,
        category
      )
    );
  }

  /**
   * Writes a warning log, skipping lazy text construction for disabled categories.
   *
   * @param message The log text or lazy text provider.
   * @param category The optional log category.
   * @param option The log category controlling output.
   */
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
      XmaxLogger.format(
        message,
        category
      )
    );
  }

  /**
   * Writes an error log, skipping lazy text construction for disabled categories.
   *
   * @param message The log text or lazy text provider.
   * @param category The optional log category.
   * @param option The log category controlling output.
   */
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
      XmaxLogger.format(
        message,
        category
      )
    );
  }

  /**
   * Prefixes log text, redacts sensitive fields, and preserves a trailing visual blank line.
   *
   * @param message The log text or lazy text provider.
   * @param category The optional log category.
   *
   * @returns The text for system logging.
   */
  private static format(
    message: LogMessage,
    category?: string
  ): string {
    const redacted: string = XmaxLogger.redact(typeof message === 'string' ? message : message());
    const normalizedCategory: string = category?.trim() ?? '';
    const categoryPrefix: string = normalizedCategory.length === 0 ? '' : `[${normalizedCategory}]`;
    const prefix: string = `${LOG_PREFIX}${categoryPrefix}`;
    const prefixed: string = redacted.replace(
      /[\r\n\u200B]+$/,
      ''
    ).replace(
      /\r\n|\r|\n/g,
      `\n${prefix} `
    );

    // DevEco omits empty log lines; a zero-width space preserves a visual separator.
    return `${prefix} ${prefixed}\n\u200B`;
  }

  /**
   * Redacts API keys, tokens, and authorization values from logs.
   *
   * @param message The log text to redact before delivery.
   *
   * @returns The redacted log text.
   */
  private static redact(
    message: string
  ): string {
    return message
      .replace(
        /(authorization\s*[:=]\s*)(?:Bearer|Basic)\s+[^\s,;]+/gi,
        '$1[REDACTED]'
      )
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
