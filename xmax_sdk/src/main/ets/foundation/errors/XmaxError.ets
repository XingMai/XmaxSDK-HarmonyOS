//
//  XmaxError.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/** An error code exposed by XmaxSDK. */
export enum XmaxErrorCode {

  /** The API key is missing or empty. */
  INVALID_API_KEY = 'INVALID_API_KEY',

  /** Arguments, configuration, or lifecycle state do not permit the operation. */
  INVALID_CONFIGURATION = 'INVALID_CONFIGURATION',

  /** An unexpected SDK failure without a more specific category. */
  INTERNAL_ERROR = 'INTERNAL_ERROR',

  /** Network unavailability, connection failure, or an incomplete HTTP request. */
  NETWORK_ERROR = 'NETWORK_ERROR',

  /** An Xmax API failure or invalid response. */
  API_ERROR = 'API_ERROR',

  /** Missing or closed realtime session data, or an invalid heartbeat state. */
  SESSION_ERROR = 'SESSION_ERROR',

  /** An RTC engine, room, media transport, or rendering binding failure. */
  RTC_ERROR = 'RTC_ERROR',

  /** A local capture, file read, decode, synchronization, or frame processing failure. */
  MEDIA_ERROR = 'MEDIA_ERROR',

  /** Camera access was not granted. */
  CAMERA_PERMISSION_DENIED = 'CAMERA_PERMISSION_DENIED',

  /** Microphone access was not granted. */
  MICROPHONE_PERMISSION_DENIED = 'MICROPHONE_PERMISSION_DENIED',

  /** File or data upload failed. */
  UPLOAD_ERROR = 'UPLOAD_ERROR',

  /** Remote file download failed. */
  DOWNLOAD_ERROR = 'DOWNLOAD_ERROR',

  /** The image failed a content safety check. */
  UNSAFE_IMAGE = 'UNSAFE_IMAGE',

  /** The operation was cancelled by lifecycle changes or your app. */
  CANCELLED = 'CANCELLED',

  /** Connection, room event, or generation confirmation timed out. */
  TIMEOUT = 'TIMEOUT'
}

/**
 * An error handler for SDK internal components.
 *
 * @param error The SDK component failure to deliver.
 */
export type XmaxErrorListener = (
  error: XmaxError
) => void;

/** An SDK error returned or delivered to your app. */
export class XmaxError extends Error {

  /** The SDK error code. */
  readonly code: XmaxErrorCode;

  /** The optional Xmax API business error code. */
  readonly apiCode?: number;

  /** The HTTP status code, absent if no response was received. */
  readonly httpStatus?: number;

  /**
   * Creates an SDK error.
   *
   * @param code The SDK error code.
   * @param message The failure reason for your app.
   * @param apiCode The optional Xmax API business error code.
   * @param httpStatus The optional HTTP response status code.
   */
  constructor(
    code: XmaxErrorCode,
    message: string,
    apiCode?: number,
    httpStatus?: number
  ) {
    super(message);
    this.name = 'XmaxError';
    this.code = code;
    this.apiCode = apiCode;
    this.httpStatus = httpStatus;
  }

  /**
   * Preserves existing XmaxError instances and normalizes unknown failures as internal errors.
   *
   * @param error The exception to normalize.
   *
   * @returns The SDK error to throw or deliver to your app.
   */
  static from(
    error: Object
  ): XmaxError {
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
