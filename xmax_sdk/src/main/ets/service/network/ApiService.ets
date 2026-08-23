import { http } from '@kit.NetworkKit';
import { ErrorMessageFormatter } from '../../foundation/errors/ErrorMessageFormatter';
import {
  XmaxError,
  XmaxErrorCode
} from '../../foundation/errors/XmaxError';
import { ApiLogger } from './ApiLogger';
import { ApiServicing } from './ApiServicing';

const API_BASE_URL: string = 'https://cloud.xmax.22duck.cn/open/api/v1';
const API_TIMEOUT_MS: number = 15000;

/** 表示 Xmax API 的统一响应结构。 */
interface ApiEnvelope {

  success?: boolean;
  code?: number;
  message?: string;
  data?: Object;
}

/** 负责发送 Xmax API 请求并统一处理响应、日志和错误。 */
export class ApiService implements ApiServicing {

  private readonly apiKey: string;

  /**
   * 创建 API Service。
   *
   * @param apiKey 调用 Xmax API 使用的访问密钥。
   */
  constructor(apiKey: string) {
    this.apiKey = apiKey;
  }

  /**
   * 发送 GET 请求。
   *
   * @param path 相对于 API 基础地址的请求路径。
   * @returns 解析后的响应数据。
   */
  get<T>(path: string): Promise<T> {
    return this.request<T>(http.RequestMethod.GET, path);
  }

  /**
   * 发送 POST 请求。
   *
   * @param path 相对于 API 基础地址的请求路径。
   * @param body 可选的请求体。
   * @returns 解析后的响应数据。
   */
  post<T>(
    path: string,
    body?: Object
  ): Promise<T> {
    return this.request<T>(http.RequestMethod.POST, path, body);
  }

  /**
   * 发送 PUT 请求。
   *
   * @param path 相对于 API 基础地址的请求路径。
   * @param body 可选的请求体。
   * @returns 解析后的响应数据。
   */
  put<T>(
    path: string,
    body?: Object
  ): Promise<T> {
    return this.request<T>(http.RequestMethod.PUT, path, body);
  }

  /**
   * 发送 DELETE 请求。
   *
   * @param path 相对于 API 基础地址的请求路径。
   * @returns 解析后的响应数据。
   */
  delete<T>(path: string): Promise<T> {
    return this.request<T>(http.RequestMethod.DELETE, path);
  }

  /**
   * 执行 HTTP 请求并统一处理网络异常、响应解析和日志记录。
   *
   * @param method HTTP 请求方法。
   * @param path 相对于 API 基础地址的请求路径。
   * @param body 可选的请求体。
   * @returns 解析后的响应数据。
   */
  private async request<T>(
    method: http.RequestMethod,
    path: string,
    body?: Object
  ): Promise<T> {
    this.validateApiKey();

    const request: http.HttpRequest = http.createHttp();
    const url: string = `${API_BASE_URL}${path}`;
    const startedAt: number = Date.now();

    try {
      let result: http.HttpResponse;

      try {
        const extraData: string | undefined = body === undefined ?
          undefined : JSON.stringify(body);

        result = await request.request(url, {
          method,
          header: this.headers(),
          extraData,
          expectDataType: http.HttpDataType.STRING,
          connectTimeout: API_TIMEOUT_MS,
          readTimeout: API_TIMEOUT_MS
        });
      } catch (error) {
        ApiLogger.logFailure(
          method,
          path,
          error,
          Date.now() - startedAt
        );

        if (error instanceof XmaxError) {
          throw error;
        }

        throw new XmaxError(
          XmaxErrorCode.NETWORK_ERROR,
          `HTTP request failed: ${this.errorMessage(error)}`
        );
      }

      const responseBody: string = result.result as string;
      const durationMs: number = Date.now() - startedAt;

      try {
        const value: T = this.parseResponse<T>(result.responseCode, responseBody);
        ApiLogger.logResponse(
          method,
          path,
          result.responseCode,
          responseBody,
          durationMs,
          true
        );

        return value;
      } catch (error) {
        ApiLogger.logResponse(
          method,
          path,
          result.responseCode,
          responseBody,
          durationMs,
          false
        );

        if (error instanceof XmaxError) {
          throw error;
        }

        throw new XmaxError(
          XmaxErrorCode.API_ERROR,
          this.errorMessage(error),
          undefined,
          result.responseCode
        );
      }
    } finally {
      request.destroy();
    }
  }

  /**
   * 校验当前 API Key 是否可用于发起请求。
   *
   * @returns 无返回值。
   */
  private validateApiKey(): void {
    if (this.apiKey.trim().length === 0) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_API_KEY,
        'API key cannot be empty'
      );
    }
  }

  /**
   * 创建 API 请求使用的公共请求头。
   *
   * @returns API 请求头。
   */
  private headers(): Record<string, string> {
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'X-Api-Key': this.apiKey
    };
  }

  /**
   * 解析并校验 API 统一响应结构。
   *
   * @param statusCode HTTP 状态码。
   * @param text 原始响应文本。
   * @returns 响应中的业务数据。
   */
  private parseResponse<T>(
    statusCode: number,
    text: string
  ): T {
    let envelope: ApiEnvelope;

    try {
      envelope = JSON.parse(text) as ApiEnvelope;
    } catch (_error) {
      throw new XmaxError(
        XmaxErrorCode.API_ERROR,
        'Server returned invalid JSON',
        undefined,
        statusCode
      );
    }

    if (statusCode >= 200 && statusCode < 300 && envelope.success === true &&
      envelope.data !== undefined) {
      return envelope.data as T;
    }

    throw new XmaxError(
      XmaxErrorCode.API_ERROR,
      envelope.message?.trim() || 'Xmax API request failed',
      envelope.code,
      statusCode
    );
  }

  /**
   * 将未知异常格式化为可读错误信息。
   *
   * @param error 待格式化的异常。
   * @returns 可读错误信息。
   */
  private errorMessage(error: Object): string {
    return ErrorMessageFormatter.format(error);
  }
}
