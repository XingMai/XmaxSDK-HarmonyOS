//
//  StorageManager.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import {
  CosError,
  CosServiceError,
  CosXmlBaseService,
  CosXmlServiceConfig,
  CosXmlUploadTaskResult,
  HttpProgress,
  PutObjectRequest,
  QCloudCredential,
  TransferConfig,
  UploadTask
} from '@tencentcloud/cos';
import {
  XmaxError,
  XmaxErrorCode
} from '../errors/XmaxError';
import { XmaxLogger } from '../logging/XmaxLogger';
import { DownloadedFile } from './DownloadedFile';
import { StorageManaging } from './StorageManaging';
import { StorageConfiguration } from './StorageConfiguration';
import { StorageProgressListener } from './StorageProgressListener';
import { StoredFile } from './StoredFile';

/** The normalized result of a third-party upload task. */
class UploadOutcome {

  // Upload result and failure details

  /** The successfully uploaded file information, if available. */
  readonly file?: StoredFile;

  /** The readable failure description, if any. */
  readonly errorMessage?: string;

  /** Creates an upload result. */
  constructor(
    file?: StoredFile,
    errorMessage?: string
  ) {
    this.file = file;
    this.errorMessage = errorMessage;
  }
}

/** An adapter for object storage uploads and HTTP file downloads. */
export class StorageManager implements StorageManaging {

  // Local file and application directory access

  /** The platform context for SDK resources. */
  private readonly context: common.Context;

  /** Creates a storage manager. */
  constructor(
    context: common.Context
  ) {
    this.context = context;
  }

  /**
   * Uploads encoded data or a local file with temporary storage credentials.
   *
   * @param source The file bytes or local path.
   * @param objectKey The storage object key.
   * @param contentType The file MIME type.
   * @param configuration The temporary storage configuration.
   * @param progress The upload progress handler.
   *
   * @returns The uploaded file information.
   */
  async upload(
    source: ArrayBuffer | string,
    objectKey: string,
    contentType: string,
    configuration: StorageConfiguration,
    progress?: StorageProgressListener
  ): Promise<StoredFile> {
    const startedAt: number = Date.now();
    let failureLogged: boolean = false;

    try {
      const clientConfiguration = new CosXmlServiceConfig(configuration.region);
      this.applyEndpoint(
        clientConfiguration,
        configuration.endpoint
      );

      const service = new CosXmlBaseService(
        this.context,
        clientConfiguration
      );
      const request = new PutObjectRequest(
        configuration.bucket,
        objectKey,
        source
      );

      request.addHeader(
        'Content-Type',
        contentType
      );
      request.credential = this.makeCredential(configuration);

      const transferConfiguration = new TransferConfig();
      if (typeof source === 'string') {
        transferConfiguration.simpleUploadLimit = fileIo.statSync(source).size + 1;
      }

      const task: UploadTask = service.upload(
        request,
        undefined,
        transferConfiguration
      );

      task.onProgress = (value: HttpProgress): void => {
        progress?.(
          value.complete,
          value.target
        );
      };

      const outcome: UploadOutcome = await new Promise<UploadOutcome>((resolve) => {
        task.onResult = {
          onSuccess: (_request: PutObjectRequest, result: CosXmlUploadTaskResult): void => {
            const url: string = this.resolveUrl(
              result.accessUrl,
              configuration,
              objectKey
            );
            const etag: string | undefined = this.nonEmpty(result.eTag);
            resolve(new UploadOutcome(new StoredFile(
              url,
              objectKey,
              etag
            )));
          },
          onFail: (_request: PutObjectRequest, error: CosError): void => {
            failureLogged = true;
            this.logUploadFailure(
              error,
              startedAt
            );
            resolve(new UploadOutcome(
              undefined,
              this.errorMessage(error)
            ));
          }
        };

        task.start();
      });

      if (outcome.file !== undefined) {
        return outcome.file;
      }

      throw new XmaxError(
        XmaxErrorCode.UPLOAD_ERROR,
        outcome.errorMessage ?? 'Storage upload returned no result'
      );
    } catch (error) {
      if (error instanceof XmaxError) {
        throw error;
      }

      if (!failureLogged) {
        this.logUploadFailure(
          error,
          startedAt
        );
      }

      throw new XmaxError(
        XmaxErrorCode.UPLOAD_ERROR,
        this.errorMessage(error)
      );
    }
  }

  /**
   * Downloads a remote file to a local path.
   *
   * @param remoteUrl The remote file URL.
   * @param destinationPath The destination file path.
   * @param progress The download progress handler.
   *
   * @returns The downloaded file information.
   */
  async download(
    remoteUrl: string,
    destinationPath: string,
    progress?: StorageProgressListener
  ): Promise<DownloadedFile> {
    const request = http.createHttp();

    try {
      const response: http.HttpResponse = await request.request(
        remoteUrl,
        {
          method: http.RequestMethod.GET,
          expectDataType: http.HttpDataType.ARRAY_BUFFER
        }
      );
      if (response.responseCode < 200 || response.responseCode >= 300 ||
        !(response.result instanceof ArrayBuffer)) {
        throw new XmaxError(
          XmaxErrorCode.DOWNLOAD_ERROR,
          `Storage download failed with HTTP ${response.responseCode}`
        );
      }

      const data: ArrayBuffer = response.result;
      const file = fileIo.openSync(
        destinationPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC
      );

      try {
        fileIo.writeSync(
          file.fd,
          data
        );
      } finally {
        fileIo.closeSync(file);
      }

      progress?.(
        data.byteLength,
        data.byteLength
      );

      return new DownloadedFile(
        destinationPath,
        data.byteLength
      );
    } catch (error) {
      if (error instanceof XmaxError) {
        throw error;
      }

      throw new XmaxError(
        XmaxErrorCode.DOWNLOAD_ERROR,
        this.errorMessage(error)
      );
    } finally {
      request.destroy();
    }
  }

  /**
   * Converts neutral storage configuration into vendor credentials.
   *
   * @param configuration The temporary storage configuration.
   *
   * @returns The vendor storage credentials.
   */
  private makeCredential(
    configuration: StorageConfiguration
  ): QCloudCredential {
    const credential = new QCloudCredential();
    credential.secretID = configuration.credential.accessKeyId;
    credential.secretKey = configuration.credential.secretAccessKey;
    credential.token = configuration.credential.sessionToken;
    credential.startDate = new Date(Date.now() - 60 * 1000);
    credential.expirationDate = new Date(Date.now() + 25 * 60 * 1000);

    if (!credential.valid()) {
      throw new XmaxError(
        XmaxErrorCode.UPLOAD_ERROR,
        'Failed to create temporary storage credential'
      );
    }

    return credential;
  }

  /**
   * Applies a neutral endpoint to vendor storage configuration.
   *
   * @param configuration The vendor storage client configuration.
   * @param endpoint The storage endpoint.
   */
  private applyEndpoint(
    configuration: CosXmlServiceConfig,
    endpoint: string
  ): void {
    let value: string = endpoint.trim();
    if (value.length === 0) {
      return;
    }

    if (value.startsWith('https://')) {
      configuration.protocol = 'https';
      value = value.substring('https://'.length);
    } else if (value.startsWith('http://')) {
      configuration.protocol = 'http';
      value = value.substring('http://'.length);
    }

    const slashIndex: number = value.indexOf('/');
    const host: string = slashIndex < 0 ? value : value.substring(
      0,
      slashIndex
    );
    configuration.host = host.startsWith('cos.') ? `\${bucket}.${host}` : host;
  }

  /**
   * Resolves a file URL from upload results and storage configuration.
   *
   * @param candidate The candidate URL returned by the vendor upload.
   * @param configuration The temporary storage configuration.
   * @param objectKey The storage object key.
   *
   * @returns The accessible file URL.
   */
  private resolveUrl(
    candidate: string | undefined,
    configuration: StorageConfiguration,
    objectKey: string
  ): string {
    const location: string = candidate?.trim() ?? '';
    if (location.startsWith('//')) {
      return `https:${location}`;
    }
    if (this.isHttpUrl(location)) {
      return location;
    }

    let endpoint: string = configuration.endpoint.trim();
    if (endpoint.length === 0) {
      endpoint = `https://${configuration.bucket}.cos.${configuration.region}.myqcloud.com`;
    } else if (!endpoint.includes('://')) {
      endpoint = `https://${endpoint}`;
    }
    endpoint = endpoint.replace(
      /\/+$/,
      ''
    );

    const schemeIndex: number = endpoint.indexOf('://');
    const hostStart: number = schemeIndex < 0 ? 0 : schemeIndex + 3;
    const hostAndPath: string = endpoint.substring(hostStart);
    if (hostAndPath.startsWith('cos.')) {
      endpoint = `${endpoint.substring(0, hostStart)}${configuration.bucket}.${hostAndPath}`;
    }

    return `${endpoint}/${this.encodeObjectKey(objectKey)}`;
  }

  /**
   * URL-encodes each path segment of an object key.
   *
   * @param objectKey The original object key.
   *
   * @returns The URL-encoded object key.
   */
  private encodeObjectKey(
    objectKey: string
  ): string {
    return objectKey.split('/')
      .map((part: string): string => encodeURIComponent(part))
      .join('/');
  }

  /**
   * Checks whether a URL uses HTTP or HTTPS.
   *
   * @param value The URL to check.
   *
   * @returns True for HTTP or HTTPS URLs.
   */
  private isHttpUrl(
    value: string
  ): boolean {
    const normalized: string = value.toLowerCase();
    return normalized.startsWith('https://') || normalized.startsWith('http://');
  }

  /**
   * Trims strings and filters empty values.
   *
   * @param value The string to process.
   *
   * @returns The nonempty string, or undefined for invalid input.
   */
  private nonEmpty(
    value: string | undefined
  ): string | undefined {
    const normalized: string = value?.trim() ?? '';
    return normalized.length === 0 ? undefined : value;
  }

  /**
   * Extracts a readable vendor storage error.
   *
   * @param error The storage error.
   *
   * @returns The readable error message.
   */
  private errorMessage(
    error: Object
  ): string {
    const message: string = error instanceof Error ? error.message.trim() : '';
    return message.length > 0 ? message : String(error);
  }

  /**
   * Logs a structured upload failure by vendor error type.
   *
   * @param error The upload error.
   * @param startedAt The upload start timestamp.
   */
  private logUploadFailure(
    error: Object,
    startedAt: number
  ): void {
    let details: string = '';
    if (error instanceof CosServiceError) {
      details = `${XmaxLogger.localized("├─ HTTP 状态：", "├─ HTTP Status: ")}${error.httpCode}\n` +
        `${XmaxLogger.localized("├─ 错误信息：", "├─ Error Message: ")}${this.errorMessage(error)}\n`;
    } else if (error instanceof CosError) {
      details = `${XmaxLogger.localized("├─ COS 错误码：", "├─ COS Error Code: ")}${error.cosErrorCode}\n` +
        `${XmaxLogger.localized("├─ 错误信息：", "├─ Error Message: ")}${this.errorMessage(error)}\n`;
    } else {
      details = `${XmaxLogger.localized("├─ 错误信息：", "├─ Error Message: ")}${this.errorMessage(error)}\n`;
    }

    XmaxLogger.error(
      `${"上传失败 (Upload Failed)\n"}${details}${XmaxLogger.localized("└─ 耗时：", "└─ Duration: ")}${this.formatDuration(Date.now() - startedAt)}`,
      'Storage'
    );
  }

  /**
   * Formats elapsed milliseconds for display.
   *
   * @param milliseconds The elapsed milliseconds.
   *
   * @returns The formatted duration.
   */
  private formatDuration(
    milliseconds: number
  ): string {
    return milliseconds < 1000 ?
      `${milliseconds} ms` : `${(milliseconds / 1000).toFixed(2)} s`;
  }
}
