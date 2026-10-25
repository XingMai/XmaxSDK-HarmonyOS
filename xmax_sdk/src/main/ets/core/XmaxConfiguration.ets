//
//  XmaxConfiguration.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { XmaxLoggerOption } from '../foundation/logging/XmaxLoggerOption';
import {
  XmaxError,
  XmaxErrorCode
} from '../foundation/errors/XmaxError';
import { XmaxEnvironment } from './XmaxEnvironment';

/** The credentials, service environment, and logging options for an Xmax client. */
export class XmaxConfiguration {

  /** The API key used to access Xmax services. */
  readonly apiKey: string;

  /**
   * The service environment and log detail language: Chinese for China, English for global. Logging
   * configuration is global.
   */
  readonly environment: XmaxEnvironment;

  /** The enabled SDK log categories; disabled by default. */
  readonly loggerOptions: XmaxLoggerOption;

  /**
   * Creates a client configuration.
   *
   * @param apiKey The API key used to access Xmax services.
   * @param environment The service environment; defaults to China.
   * @param loggerOptions The log categories combined with bitwise OR; defaults to disabled.
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

  /** Verifies the configuration, throwing an XmaxError if invalid. */
  validate(): void {
    if (this.apiKey.length === 0) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_API_KEY,
        'API key cannot be empty'
      );
    }
  }
}
