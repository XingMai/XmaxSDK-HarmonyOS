//
//  XmaxLogger.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { hilog } from '@kit.PerformanceAnalysisKit';
import { XmaxLoggerOption } from './XmaxLoggerOption';
import { XmaxEnvironment } from '../../core/XmaxEnvironment';

const LOG_DOMAIN: number = 0x584D;
const LOG_TAG: string = 'XmaxSDK';
const LOG_PREFIX: string = '[Xmax]';

/** 日志文本或延迟构造文本的函数；关闭对应日志时无需构造内容。 */
type LogMessage = string | (() => string);

/** SDK 内部日志入口；调用方不应传入认证信息或完整敏感响应。 */
export class XmaxLogger {

  /** 全局日志筛选与语言配置 */
  private static options: XmaxLoggerOption = XmaxLoggerOption.NONE;
  private static environment: XmaxEnvironment = XmaxEnvironment.CHINA;

  /**
   * 配置 SDK 全局日志；新客户端的配置会覆盖之前的配置。
   *
   * @param options 组件使用的初始化选项。
   * @param environment SDK 连接的服务环境。
   * @returns 无返回值。
   */
  static configure(options: XmaxLoggerOption, environment: XmaxEnvironment = XmaxEnvironment.CHINA): void {
    XmaxLogger.options = options;
    XmaxLogger.environment = environment;
  }

  /**
   * 日志标题保留中英双语，细项跟随最后创建的 Client 的服务环境。
   *
   * @param chinese 面向中国服务环境使用的中文文本。
   * @param english 其他服务环境使用的英文文本。
   * @returns 中国服务环境返回中文文本，其他环境返回英文文本。
   */
  static localized(chinese: string, english: string): string {
    return XmaxLogger.environment === XmaxEnvironment.CHINA ? chinese : english;
  }

  /**
   * 判断指定日志类别是否已启用。
   *
   * @param option 决定是否输出此日志的日志选项。
   * @returns 类别与当前日志配置匹配时返回 true。
   */
  static isEnabled(option: XmaxLoggerOption): boolean {
    return option !== XmaxLoggerOption.NONE && (XmaxLogger.options & option) === option;
  }

  /**
   * 输出调试级别日志；对应类别关闭时跳过延迟文本构造。
   *
   * @param message 直接日志文本或按需构造日志文本的函数。
   * @param category 可选的日志业务分类。
   * @param option 决定是否输出此日志的日志选项。
   * @returns 无返回值。
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
      XmaxLogger.format(message, category)
    );
  }

  /**
   * 输出信息级别日志；对应类别关闭时跳过延迟文本构造。
   *
   * @param message 直接日志文本或按需构造日志文本的函数。
   * @param category 可选的日志业务分类。
   * @param option 决定是否输出此日志的日志选项。
   * @returns 无返回值。
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
      XmaxLogger.format(message, category)
    );
  }

  /**
   * 输出警告级别日志；对应类别关闭时跳过延迟文本构造。
   *
   * @param message 直接日志文本或按需构造日志文本的函数。
   * @param category 可选的日志业务分类。
   * @param option 决定是否输出此日志的日志选项。
   * @returns 无返回值。
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
      XmaxLogger.format(message, category)
    );
  }

  /**
   * 输出错误级别日志；对应类别关闭时跳过延迟文本构造。
   *
   * @param message 直接日志文本或按需构造日志文本的函数。
   * @param category 可选的日志业务分类。
   * @param option 决定是否输出此日志的日志选项。
   * @returns 无返回值。
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
      XmaxLogger.format(message, category)
    );
  }

  /**
   * 构造日志文本，添加 SDK 分类标记、遮蔽敏感字段，并在末尾保留一行空白。
   *
   * @param message 直接日志文本或按需构造日志文本的函数。
   * @param category 可选的日志业务分类。
   * @returns 可直接交给系统日志输出的文本。
   */
  private static format(
    message: LogMessage,
    category?: string
  ): string {
    const redacted: string = XmaxLogger.redact(typeof message === 'string' ? message : message());
    const normalizedCategory: string = category?.trim() ?? '';
    const categoryPrefix: string = normalizedCategory.length === 0 ? '' : `[${normalizedCategory}]`;
    const prefix: string = `${LOG_PREFIX}${categoryPrefix}`;
    const prefixed: string = redacted.replace(/[\r\n\u200B]+$/, '').replace(
      /\r\n|\r|\n/g,
      `\n${prefix} `
    );

    // DevEco 会忽略纯空行；用零宽空格保留日志之间的视觉空行。
    return `${prefix} ${prefixed}\n\u200B`;
  }

  /**
   * 遮蔽日志中的 API 密钥、令牌和授权信息。
   *
   * @param message 日志内容、错误说明或收到的信令文本。
   * @returns 已完成敏感信息脱敏的日志文本。
   */
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
