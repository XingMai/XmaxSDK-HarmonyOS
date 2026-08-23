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
import { StorageProviding } from './StorageProviding';
import { StorageConfiguration } from './StorageConfiguration';
import { StorageProgressListener } from './StorageProgressListener';
import { StoredFile } from './StoredFile';

/** 保存第三方存储上传任务的统一结果。 */
class UploadOutcome {

  readonly file?: StoredFile;
  readonly errorMessage?: string;

  /**
   * 创建上传结果。
   *
   * @param file 上传成功后的文件信息。
   * @param errorMessage 上传失败时的错误信息。
   */
  constructor(
    file?: StoredFile,
    errorMessage?: string
  ) {
    this.file = file;
    this.errorMessage = errorMessage;
  }
}

/** 封装第三方对象存储的文件上传和 HTTP 文件下载能力。 */
export class StorageProvider implements StorageProviding {

  private readonly context: common.Context;

  /**
   * 创建存储 Provider。
   *
   * @param context 第三方存储客户端使用的平台上下文。
   */
  constructor(context: common.Context) {
    this.context = context;
  }

  /**
   * 使用临时存储配置上传二进制数据或本地文件。
   *
   * @param source 文件二进制数据或本地文件路径。
   * @param objectKey 存储对象标识。
   * @param contentType 文件内容类型。
   * @param configuration 临时存储配置。
   * @param progress 上传进度监听器。
   * @returns 上传后的文件信息。
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
      this.applyEndpoint(clientConfiguration, configuration.endpoint);

      const service = new CosXmlBaseService(this.context, clientConfiguration);
      const request = new PutObjectRequest(configuration.bucket, objectKey, source);

      request.addHeader('Content-Type', contentType);
      request.credential = this.makeCredential(configuration);

      const transferConfiguration = new TransferConfig();
      if (typeof source === 'string') {
        transferConfiguration.simpleUploadLimit = fileIo.statSync(source).size + 1;
      }
      const task: UploadTask = service.upload(request, undefined, transferConfiguration);
      task.onProgress = (value: HttpProgress): void => {
        progress?.(value.complete, value.target);
      };

      const outcome: UploadOutcome = await new Promise<UploadOutcome>((resolve) => {
        task.onResult = {
          onSuccess: (_request: PutObjectRequest, result: CosXmlUploadTaskResult): void => {
            const url: string = this.resolveUrl(result.accessUrl, configuration, objectKey);
            const etag: string | undefined = this.nonEmpty(result.eTag);
            resolve(new UploadOutcome(new StoredFile(url, objectKey, etag)));
          },
          onFail: (_request: PutObjectRequest, error: CosError): void => {
            failureLogged = true;
            this.logUploadFailure(error, startedAt);
            resolve(new UploadOutcome(undefined, this.errorMessage(error)));
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
        this.logUploadFailure(error, startedAt);
      }
      throw new XmaxError(XmaxErrorCode.UPLOAD_ERROR, this.errorMessage(error));
    }
  }

  /**
   * 下载远端文件并写入指定本地路径。
   *
   * @param remoteUrl 远端文件地址。
   * @param destinationPath 本地目标路径。
   * @param progress 下载进度监听器。
   * @returns 下载后的文件信息。
   */
  async download(
    remoteUrl: string,
    destinationPath: string,
    progress?: StorageProgressListener
  ): Promise<DownloadedFile> {
    const request = http.createHttp();

    try {
      const response: http.HttpResponse = await request.request(remoteUrl, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      });
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
        fileIo.writeSync(file.fd, data);
      } finally {
        fileIo.closeSync(file);
      }

      progress?.(data.byteLength, data.byteLength);

      return new DownloadedFile(destinationPath, data.byteLength);
    } catch (error) {
      if (error instanceof XmaxError) {
        throw error;
      }
      throw new XmaxError(XmaxErrorCode.DOWNLOAD_ERROR, this.errorMessage(error));
    } finally {
      request.destroy();
    }
  }

  /**
   * 将中性存储配置转换为第三方临时凭证。
   *
   * @param configuration 临时存储配置。
   * @returns 第三方存储凭证。
   */
  private makeCredential(configuration: StorageConfiguration): QCloudCredential {
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
   * 将中性服务地址应用到第三方存储客户端配置。
   *
   * @param configuration 第三方存储客户端配置。
   * @param endpoint 存储服务地址。
   * @returns 无返回值。
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
    const host: string = slashIndex < 0 ? value : value.substring(0, slashIndex);
    configuration.host = host.startsWith('cos.') ? `\${bucket}.${host}` : host;
  }

  /**
   * 根据上传结果和存储配置解析文件访问地址。
   *
   * @param candidate 第三方上传结果返回的候选地址。
   * @param configuration 临时存储配置。
   * @param objectKey 存储对象标识。
   * @returns 可访问的文件地址。
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
    endpoint = endpoint.replace(/\/+$/, '');
    const schemeIndex: number = endpoint.indexOf('://');
    const hostStart: number = schemeIndex < 0 ? 0 : schemeIndex + 3;
    const hostAndPath: string = endpoint.substring(hostStart);
    if (hostAndPath.startsWith('cos.')) {
      endpoint = `${endpoint.substring(0, hostStart)}${configuration.bucket}.${hostAndPath}`;
    }
    return `${endpoint}/${this.encodeObjectKey(objectKey)}`;
  }

  /**
   * 对对象键的各级路径片段进行 URL 编码。
   *
   * @param objectKey 原始对象键。
   * @returns URL 编码后的对象键。
   */
  private encodeObjectKey(objectKey: string): string {
    return objectKey.split('/')
      .map((part: string): string => encodeURIComponent(part))
      .join('/');
  }

  /**
   * 判断地址是否使用 HTTP 或 HTTPS 协议。
   *
   * @param value 待检查地址。
   * @returns 地址使用 HTTP 或 HTTPS 协议时返回 true，否则返回 false。
   */
  private isHttpUrl(value: string): boolean {
    const normalized: string = value.toLowerCase();
    return normalized.startsWith('https://') || normalized.startsWith('http://');
  }

  /**
   * 清理字符串并过滤空值。
   *
   * @param value 待处理字符串。
   * @returns 非空字符串；输入无效时返回空值。
   */
  private nonEmpty(value: string | undefined): string | undefined {
    const normalized: string = value?.trim() ?? '';
    return normalized.length === 0 ? undefined : value;
  }

  /**
   * 获取第三方存储异常的可读错误信息。
   *
   * @param error 存储异常。
   * @returns 可读错误信息。
   */
  private errorMessage(error: Object): string {
    const message: string = error instanceof Error ? error.message.trim() : '';
    return message.length > 0 ? message : String(error);
  }

  /**
   * 按第三方错误类型记录结构化上传失败日志。
   *
   * @param error 上传异常。
   * @param startedAt 上传开始时间戳。
   * @returns 无返回值。
   */
  private logUploadFailure(error: Object, startedAt: number): void {
    let details: string = '';
    if (error instanceof CosServiceError) {
      details = `├─ HTTP 状态：${error.httpCode}\n` +
        `├─ 错误信息：${this.errorMessage(error)}\n`;
    } else if (error instanceof CosError) {
      details = `├─ COS 错误码：${error.cosErrorCode}\n` +
        `├─ 错误信息：${this.errorMessage(error)}\n`;
    } else {
      details = `├─ 错误信息：${this.errorMessage(error)}\n`;
    }

    XmaxLogger.error(
      `上传失败\n${details}└─ 耗时：${this.formatDuration(Date.now() - startedAt)}`,
      'Storage'
    );
  }

  /**
   * 将毫秒耗时格式化为便于阅读的时间文本。
   *
   * @param milliseconds 耗时毫秒数。
   * @returns 格式化后的耗时文本。
   */
  private formatDuration(milliseconds: number): string {
    return milliseconds < 1000 ?
      `${milliseconds} ms` : `${(milliseconds / 1000).toFixed(2)} s`;
  }
}
