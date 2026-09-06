/** SDK 向接入方暴露的统一错误码。 */
export enum XmaxErrorCode {

  /** API Key 未配置或为空。 */
  INVALID_API_KEY = 'INVALID_API_KEY',

  /** 调用参数、配置或当前生命周期状态不符合操作要求。 */
  INVALID_CONFIGURATION = 'INVALID_CONFIGURATION',

  /** SDK 内部发生无法归类的非预期错误。 */
  INTERNAL_ERROR = 'INTERNAL_ERROR',

  /** 网络不可用、连接失败或 HTTP 请求无法完成。 */
  NETWORK_ERROR = 'NETWORK_ERROR',

  /** Xmax API 返回业务失败，或者响应数据无法正确解析。 */
  API_ERROR = 'API_ERROR',

  /** 实时生成会话数据缺失、会话关闭或心跳状态异常。 */
  SESSION_ERROR = 'SESSION_ERROR',

  /** RTC Engine、房间、媒体传输或渲染绑定发生错误。 */
  RTC_ERROR = 'RTC_ERROR',

  /** 本地媒体读取、解码、同步或帧处理发生错误。 */
  MEDIA_ERROR = 'MEDIA_ERROR',

  /** 接入方未授予相机权限。 */
  CAMERA_PERMISSION_DENIED = 'CAMERA_PERMISSION_DENIED',

  /** 接入方未授予麦克风权限。 */
  MICROPHONE_PERMISSION_DENIED = 'MICROPHONE_PERMISSION_DENIED',

  /** 文件或二进制数据上传失败。 */
  UPLOAD_ERROR = 'UPLOAD_ERROR',

  /** 远端文件下载失败。 */
  DOWNLOAD_ERROR = 'DOWNLOAD_ERROR',

  /** 图片未通过内容安全检查。 */
  UNSAFE_IMAGE = 'UNSAFE_IMAGE',

  /** 操作因生命周期切换或接入方主动终止而正常取消。 */
  CANCELLED = 'CANCELLED',

  /** 等待连接、房间事件或生成结果超过规定时间。 */
  TIMEOUT = 'TIMEOUT'
}

/** 描述错误对当前操作或实时流程的影响。 */
export enum XmaxErrorSeverity {
  /** 当前操作失败，SDK 仍可继续使用。 */
  RECOVERABLE = 'RECOVERABLE',
  /** 当前实时流程无法继续，需要接入方恢复或退出。 */
  FATAL = 'FATAL'
}

/** SDK 内部组件使用的错误监听器，包含所有错误级别。 */
export type XmaxErrorListener = (error: XmaxError) => void;

/** 表示 SDK 统一抛出或回调给接入方的错误。 */
export class XmaxError extends Error {

  /** SDK 统一错误码。 */
  readonly code: XmaxErrorCode;

  /** 错误对当前操作或实时流程的影响程度。 */
  readonly severity: XmaxErrorSeverity;

  /** Xmax API 返回的业务错误码；非 API 业务错误时为空。 */
  readonly apiCode?: number;

  /** HTTP 响应状态码；请求未获得响应时为空。 */
  readonly httpStatus?: number;

  /**
   * 创建 SDK 错误。
   *
   * @param code SDK 统一错误码。
   * @param message 面向接入方的错误原因。
   * @param apiCode Xmax API 返回的可选业务错误码。
   * @param httpStatus 可选的 HTTP 响应状态码。
   * @param severity 错误级别；默认根据错误码决定。放在末尾以兼容原有参数顺序。
   */
  constructor(
    code: XmaxErrorCode,
    message: string,
    apiCode?: number,
    httpStatus?: number,
    severity?: XmaxErrorSeverity
  ) {
    super(message);
    this.name = 'XmaxError';
    this.code = code;
    this.severity = severity ?? XmaxError.defaultSeverity(code);
    this.apiCode = apiCode;
    this.httpStatus = httpStatus;
  }

  /** @internal 保留错误信息，并按当前操作的影响调整级别。 */
  withSeverity(severity: XmaxErrorSeverity): XmaxError {
    if (severity === this.severity) {
      return this;
    }
    return new XmaxError(this.code, this.message, this.apiCode, this.httpStatus, severity);
  }

  private static defaultSeverity(code: XmaxErrorCode): XmaxErrorSeverity {
    switch (code) {
      case XmaxErrorCode.INVALID_API_KEY:
      case XmaxErrorCode.INVALID_CONFIGURATION:
      case XmaxErrorCode.CAMERA_PERMISSION_DENIED:
      case XmaxErrorCode.MICROPHONE_PERMISSION_DENIED:
      case XmaxErrorCode.CANCELLED:
        return XmaxErrorSeverity.RECOVERABLE;
      default:
        return XmaxErrorSeverity.FATAL;
    }
  }

  /**
   * 将无法识别的异常转换为 SDK 内部错误，已有 `XmaxError` 原样返回。
   *
   * @param error 待转换的异常对象。
   * @returns 可向接入方抛出或回调的统一错误。
   */
  static from(error: Object): XmaxError {
    if (error instanceof XmaxError) {
      return error;
    }

    const message: string = error instanceof Error ?
      error.message : String(error);

    return new XmaxError(
      XmaxErrorCode.INTERNAL_ERROR,
      message
    );
  }
}
