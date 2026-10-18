//
//  XmaxConfiguration.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { XmaxLoggerOption } from '../foundation/logging/XmaxLoggerOption';
import {
  XmaxError,
  XmaxErrorCode
} from '../foundation/errors/XmaxError';
import { XmaxEnvironment } from './XmaxEnvironment';

/** SDK 全局配置。 */
export class XmaxConfiguration {

  /** 访问凭证与服务环境 */
  /** 调用 Xmax 服务使用的 API Key。 */
  readonly apiKey: string;

  /** SDK 连接的服务环境；同时决定日志细项语言，国内为中文，海外为英文。日志配置全局生效。 */
  readonly environment: XmaxEnvironment;

  /** 日志配置 */
  /** SDK 全局日志选项；默认为关闭。 */
  readonly loggerOptions: XmaxLoggerOption;

  /**
   * 创建 SDK 全局配置。
   *
   * @param apiKey 调用 Xmax 服务使用的 API Key。
   * @param environment SDK 连接的服务环境；省略时使用国内环境。
   * @param loggerOptions SDK 输出的日志类型，可按位或组合；省略时关闭日志。
   * @returns 新建的 XmaxConfiguration 实例。
   */
  constructor(
    apiKey: string,
    environment: XmaxEnvironment = XmaxEnvironment.CHINA,
    loggerOptions: XmaxLoggerOption = XmaxLoggerOption.NONE
  ) {
    this.apiKey = apiKey.trim();
    this.environment = environment;
    this.loggerOptions = loggerOptions;
  }

  /**
   * 校验全局配置，配置无效时抛出对应的 `XmaxError`。
   *
   * @returns 无返回值。
   */
  validate(): void {
    if (this.apiKey.length === 0) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_API_KEY,
        'API key cannot be empty'
      );
    }
  }
}
