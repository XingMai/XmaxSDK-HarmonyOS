import { XmaxLoggerOption } from '../foundation/logging/XmaxLoggerOption';
import {
  XmaxError,
  XmaxErrorCode
} from '../foundation/errors/XmaxError';
import { XmaxEnvironment } from './XmaxEnvironment';

/** SDK 全局配置。 */
export class XmaxConfiguration {

  /** 调用 Xmax 服务使用的 API Key。 */
  readonly apiKey: string;

  /** SDK 连接的服务环境。 */
  readonly environment: XmaxEnvironment;

  /** SDK 全局日志选项；默认为关闭。 */
  readonly loggerOptions: XmaxLoggerOption;

  /**
   * 创建 SDK 全局配置。
   *
   * @param apiKey 调用 Xmax 服务使用的 API Key。
   * @param environmentOrLoggerOptions SDK 连接的服务环境；也兼容旧版第二参数日志选项。
   * @param loggerOptions SDK 输出的日志类型，可按位或组合。
   */
  constructor(
    apiKey: string,
    environmentOrLoggerOptions: XmaxEnvironment | XmaxLoggerOption = XmaxEnvironment.CHINA,
    loggerOptions: XmaxLoggerOption = XmaxLoggerOption.NONE
  ) {
    this.apiKey = apiKey.trim();
    if (typeof environmentOrLoggerOptions === 'number') {
      this.environment = XmaxEnvironment.CHINA;
      this.loggerOptions = environmentOrLoggerOptions;
    } else {
      this.environment = environmentOrLoggerOptions;
      this.loggerOptions = loggerOptions;
    }
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
