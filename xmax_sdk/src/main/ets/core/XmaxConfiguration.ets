import {
  XmaxError,
  XmaxErrorCode
} from '../foundation/errors/XmaxError';

/** SDK 全局配置。 */
export class XmaxConfiguration {

  /** 调用 Xmax 服务使用的 API Key。 */
  readonly apiKey: string;

  /**
   * 创建 SDK 全局配置。
   *
   * @param apiKey 调用 Xmax 服务使用的 API Key。
   */
  constructor(apiKey: string) {
    this.apiKey = apiKey.trim();
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
