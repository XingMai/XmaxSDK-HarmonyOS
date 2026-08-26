import {
  uri,
  util
} from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { media } from '@kit.MediaKit';
import {
  XmaxError,
  XmaxErrorCode
} from '../../foundation/errors/XmaxError';
import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import { DownloadedFile } from '../../foundation/storage/DownloadedFile';
import { StorageManaging } from '../../foundation/storage/StorageManaging';
import { StorageConfiguration } from '../../foundation/storage/StorageConfiguration';
import { StorageCredential } from '../../foundation/storage/StorageCredential';
import { StorageProgressListener } from '../../foundation/storage/StorageProgressListener';
import { StoredFile } from '../../foundation/storage/StoredFile';
import { ApiServicing } from '../network/ApiServicing';
import { StorageServicing } from './StorageServicing';

/** 保存一次上传使用的临时存储配置和对象路径前缀。 */
class TemporaryStorageConfiguration {

  readonly prefix: string;
  readonly configuration: StorageConfiguration;

  /**
   * 创建临时存储配置。
   *
   * @param prefix 上传对象使用的路径前缀。
   * @param configuration 基础层存储 Manager 使用的配置。
   */
  constructor(
    prefix: string,
    configuration: StorageConfiguration
  ) {
    this.prefix = prefix;
    this.configuration = configuration;
  }
}

/** 表示存储操作支持的媒体类型。 */
enum StorageMediaType {

  IMAGE = 'image',
  VIDEO = 'video'
}

/** 协调图片和视频的上传、下载、临时凭证及图片安全检查。 */
export class StorageService implements StorageServicing {

  // 服务层组件
  private readonly apiService: ApiServicing;

  // 基础层组件
  private readonly storageManager: StorageManaging;

  /**
   * 创建存储 Service。
   *
   * @param apiService 提供临时凭证和图片安全检查请求能力的 API Service。
   * @param storageManager 提供文件上传和下载能力的存储 Manager。
   */
  constructor(
    apiService: ApiServicing,
    storageManager: StorageManaging
  ) {
    this.apiService = apiService;
    this.storageManager = storageManager;
  }

  /**
   * 上传图片二进制数据。
   *
   * @param data 图片二进制数据。
   * @param fileName 文件名称。
   * @param contentType 图片内容类型。
   * @param progress 上传进度监听器。
   * @returns 上传后的文件信息。
   */
  async uploadImage(
    data: ArrayBuffer,
    fileName: string,
    contentType: string,
    progress?: StorageProgressListener
  ): Promise<StoredFile> {
    return this.upload(data, fileName, contentType, StorageMediaType.IMAGE, false, progress);
  }

  /**
   * 上传本地图片文件。
   *
   * @param filePath 本地图片文件路径。
   * @param contentType 图片内容类型；未传入时根据扩展名推断。
   * @param progress 上传进度监听器。
   * @returns 上传后的文件信息。
   */
  async uploadImageFile(
    filePath: string,
    contentType?: string,
    progress?: StorageProgressListener
  ): Promise<StoredFile> {
    const fileName: string = this.lastPathComponent(filePath);
    return this.upload(
      filePath,
      fileName,
      contentType ?? this.inferImageContentType(fileName),
      StorageMediaType.IMAGE,
      false,
      progress
    );
  }

  /**
   * 上传图片二进制数据并执行内容安全检查。
   *
   * @param data 图片二进制数据。
   * @param fileName 文件名称。
   * @param contentType 图片内容类型。
   * @param progress 上传进度监听器。
   * @returns 上传并通过安全检查后的文件信息。
   */
  async uploadImageWithSafetyCheck(
    data: ArrayBuffer,
    fileName: string,
    contentType: string,
    progress?: StorageProgressListener
  ): Promise<StoredFile> {
    return this.upload(data, fileName, contentType, StorageMediaType.IMAGE, true, progress);
  }

  /**
   * 上传本地图片文件并执行内容安全检查。
   *
   * @param filePath 本地图片文件路径。
   * @param contentType 图片内容类型；未传入时根据扩展名推断。
   * @param progress 上传进度监听器。
   * @returns 上传并通过安全检查后的文件信息。
   */
  async uploadImageFileWithSafetyCheck(
    filePath: string,
    contentType?: string,
    progress?: StorageProgressListener
  ): Promise<StoredFile> {
    const fileName: string = this.lastPathComponent(filePath);
    return this.upload(
      filePath,
      fileName,
      contentType ?? this.inferImageContentType(fileName),
      StorageMediaType.IMAGE,
      true,
      progress
    );
  }

  /**
   * 上传视频二进制数据。
   *
   * @param data 视频二进制数据。
   * @param fileName 文件名称。
   * @param contentType 视频内容类型。
   * @param progress 上传进度监听器。
   * @returns 上传后的文件信息。
   */
  async uploadVideo(
    data: ArrayBuffer,
    fileName: string,
    contentType: string,
    progress?: StorageProgressListener
  ): Promise<StoredFile> {
    return this.upload(data, fileName, contentType, StorageMediaType.VIDEO, false, progress);
  }

  /**
   * 上传本地视频文件。
   *
   * @param filePath 本地视频文件路径。
   * @param contentType 视频内容类型；未传入时根据扩展名推断。
   * @param progress 上传进度监听器。
   * @returns 上传后的文件信息。
   */
  async uploadVideoFile(
    filePath: string,
    contentType?: string,
    progress?: StorageProgressListener
  ): Promise<StoredFile> {
    const fileName: string = this.lastPathComponent(filePath);
    return this.upload(
      filePath,
      fileName,
      contentType ?? this.inferVideoContentType(fileName),
      StorageMediaType.VIDEO,
      false,
      progress
    );
  }

  /**
   * 下载远端图片到本地文件。
   *
   * @param remoteUrl 远端图片地址。
   * @param destinationPath 本地目标路径。
   * @param progress 下载进度监听器。
   * @returns 下载后的文件信息。
   */
  async downloadImage(
    remoteUrl: string,
    destinationPath: string,
    progress?: StorageProgressListener
  ): Promise<DownloadedFile> {
    this.validateDownload(remoteUrl, destinationPath);
    return this.storageManager.download(remoteUrl, destinationPath, progress);
  }

  /**
   * 下载远端视频到本地文件。
   *
   * @param remoteUrl 远端视频地址。
   * @param destinationPath 本地目标路径。
   * @param progress 下载进度监听器。
   * @returns 下载后的文件信息。
   */
  async downloadVideo(
    remoteUrl: string,
    destinationPath: string,
    progress?: StorageProgressListener
  ): Promise<DownloadedFile> {
    this.validateDownload(remoteUrl, destinationPath);
    return this.storageManager.download(remoteUrl, destinationPath, progress);
  }

  /**
   * 执行统一上传流程，并按需调用图片安全检查。
   *
   * @param source 文件二进制数据或本地路径。
   * @param fileName 文件名称。
   * @param contentType 文件内容类型。
   * @param mediaType 文件媒体类型。
   * @param checksSafety 是否执行图片安全检查。
   * @param progress 上传进度监听器。
   * @returns 上传后的文件信息。
   */
  private async upload(
    source: ArrayBuffer | string,
    fileName: string,
    contentType: string,
    mediaType: StorageMediaType,
    checksSafety: boolean,
    progress?: StorageProgressListener
  ): Promise<StoredFile> {
    const startedAt: number = Date.now();
    try {
      const safeName: string = this.validateUpload(
        source,
        fileName,
        contentType,
        mediaType
      );
      const byteCount: number = this.sourceByteCount(source);
      const resolution: string = await this.readResolution(source, mediaType);
      XmaxLogger.info(
        `开始上传\n` +
        `├─ 类型：${mediaType}\n` +
        `├─ 分辨率：${resolution}\n` +
        `├─ 大小：${this.formatByteCount(byteCount)}\n` +
        `└─ 安全检测：${checksSafety}`,
        'Storage'
      );

      const temporary: TemporaryStorageConfiguration =
        await this.fetchStorageConfiguration();
      const objectKey: string = this.makeObjectKey(temporary.prefix, safeName);

      const stored: StoredFile = await this.storageManager.upload(
        source,
        objectKey,
        contentType.trim(),
        temporary.configuration,
        progress
      );

      let result: StoredFile = stored;
      if (checksSafety) {
        const checkedUrl: string = await this.checkImage(stored.url);
        result = new StoredFile(checkedUrl, stored.objectKey, stored.etag);
      }

      XmaxLogger.info(
        `上传完成\n` +
        `├─ 地址：${result.url}\n` +
        `└─ 耗时：${this.formatDuration(Date.now() - startedAt)}`,
        'Storage'
      );
      return result;
    } catch (error) {
      if (!(error instanceof XmaxError && error.code === XmaxErrorCode.UPLOAD_ERROR)) {
        XmaxLogger.error(
          `上传失败\n` +
          `├─ 错误码：${this.errorCode(error)}\n` +
          `├─ 原因：${this.errorMessage(error)}\n` +
          `└─ 耗时：${this.formatDuration(Date.now() - startedAt)}`,
          'Storage'
        );
      }
      if (error instanceof Error) {
        throw error;
      }
      throw new XmaxError(XmaxErrorCode.UPLOAD_ERROR, String(error));
    }
  }

  /**
   * 获取上传源的字节数。
   *
   * @param source 文件二进制数据或本地路径。
   * @returns 上传源的字节数。
   */
  private sourceByteCount(source: ArrayBuffer | string): number {
    return typeof source === 'string' ? fileIo.statSync(source).size : source.byteLength;
  }

  /**
   * 尝试读取上传媒体的显示分辨率。
   *
   * @param source 文件二进制数据或本地路径。
   * @param mediaType 文件媒体类型。
   * @returns 格式化后的分辨率；无法读取时返回占位文本。
   */
  private async readResolution(
    source: ArrayBuffer | string,
    mediaType: StorageMediaType
  ): Promise<string> {
    try {
      return mediaType === StorageMediaType.IMAGE ?
        await this.readImageResolution(source) :
        await this.readVideoResolution(source);
    } catch (_error) {
      return '--';
    }
  }

  /**
   * 读取图片上传源的分辨率。
   *
   * @param source 图片二进制数据或本地路径。
   * @returns 格式化后的图片分辨率。
   */
  private async readImageResolution(source: ArrayBuffer | string): Promise<string> {
    const imageSource: image.ImageSource = typeof source === 'string' ?
      image.createImageSource(source) : image.createImageSource(source);
    try {
      const info: image.ImageInfo = await imageSource.getImageInfo();
      return this.formatResolution(info.size.width, info.size.height);
    } finally {
      await imageSource.release();
    }
  }

  /**
   * 读取本地视频文件考虑旋转方向后的显示分辨率。
   *
   * @param source 视频二进制数据或本地路径。
   * @returns 格式化后的视频分辨率；二进制输入无法读取时返回占位文本。
   */
  private async readVideoResolution(source: ArrayBuffer | string): Promise<string> {
    if (typeof source !== 'string') {
      return '--';
    }

    const sourceFile: fileIo.File = fileIo.openSync(source, fileIo.OpenMode.READ_ONLY);
    let extractor: media.AVMetadataExtractor | null = null;
    try {
      extractor = await media.createAVMetadataExtractor();
      extractor.fdSrc = {
        fd: sourceFile.fd,
        offset: 0,
        length: fileIo.statSync(sourceFile.fd).size
      };
      const metadata: media.AVMetadata = await extractor.fetchMetadata();
      const width: number = Number.parseInt(metadata.videoWidth ?? '');
      const height: number = Number.parseInt(metadata.videoHeight ?? '');
      const rotation: number = Number.parseInt(metadata.videoOrientation ?? '0');
      const normalizedRotation: number = Number.isFinite(rotation) ?
        ((rotation % 360) + 360) % 360 : 0;
      return normalizedRotation === 90 || normalizedRotation === 270 ?
        this.formatResolution(height, width) :
        this.formatResolution(width, height);
    } finally {
      try {
        if (extractor !== null) {
          await extractor.release();
        }
      } finally {
        fileIo.closeSync(sourceFile);
      }
    }
  }

  /**
   * 将有效宽高格式化为分辨率文本。
   *
   * @param width 媒体宽度。
   * @param height 媒体高度。
   * @returns 格式化后的分辨率；宽高无效时返回占位文本。
   */
  private formatResolution(width: number, height: number): string {
    if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) {
      return '--';
    }
    return `${width} × ${height}`;
  }

  /**
   * 将字节数格式化为便于阅读的容量文本。
   *
   * @param byteCount 文件字节数。
   * @returns 格式化后的容量文本。
   */
  private formatByteCount(byteCount: number): string {
    if (byteCount < 1024) {
      return `${byteCount} B`;
    }
    if (byteCount < 1024 * 1024) {
      return `${(byteCount / 1024).toFixed(1)} KB`;
    }
    if (byteCount < 1024 * 1024 * 1024) {
      return `${(byteCount / (1024 * 1024)).toFixed(2)} MB`;
    }
    return `${(byteCount / (1024 * 1024 * 1024)).toFixed(2)} GB`;
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

  /**
   * 获取上传异常对应的 SDK 错误码。
   *
   * @param error 上传异常。
   * @returns SDK 错误码。
   */
  private errorCode(error: Object): string {
    return error instanceof XmaxError ? error.code : XmaxErrorCode.UPLOAD_ERROR;
  }

  /**
   * 获取上传异常的可读错误信息。
   *
   * @param error 上传异常。
   * @returns 可读错误信息。
   */
  private errorMessage(error: Object): string {
    const message: string = error instanceof Error ? error.message.trim() : '';
    return message.length > 0 ? message : String(error);
  }

  /**
   * 请求并解析一次上传使用的临时存储配置。
   *
   * @returns 临时存储配置。
   */
  private async fetchStorageConfiguration(): Promise<TemporaryStorageConfiguration> {
    const value = await this.apiService.get<Object>('/cos/sts');
    const record: Record<string, Object> = this.toRecord(
      value,
      'Invalid storage credential payload'
    );

    const credentials: Record<string, Object> = this.toRecord(
      record['credentials'],
      'Invalid storage credential payload'
    );

    const bucket: string = this.requiredString(
      record,
      'bucket',
      'Invalid storage credential payload'
    );
    const region: string = this.requiredString(
      record,
      'region',
      'Invalid storage credential payload'
    );
    const endpoint: string = this.requiredString(
      record,
      'endpoint',
      'Invalid storage credential payload'
    );
    const prefix: string = this.requiredString(
      record,
      'prefix',
      'Invalid storage credential payload'
    );

    const accessKeyId: string = this.requiredString(
      credentials,
      'accessKeyId',
      'Invalid storage credential payload'
    );
    const secretAccessKey: string = this.requiredString(
      credentials,
      'secretAccessKey',
      'Invalid storage credential payload'
    );
    const sessionToken: string = this.requiredString(
      credentials,
      'sessionToken',
      'Invalid storage credential payload'
    );

    if (bucket.length === 0 || region.length === 0 || accessKeyId.length === 0 ||
      secretAccessKey.length === 0 || sessionToken.length === 0) {
      throw new XmaxError(XmaxErrorCode.API_ERROR, 'Invalid storage credential payload');
    }

    return new TemporaryStorageConfiguration(
      prefix,
      new StorageConfiguration(
        bucket,
        region,
        endpoint,
        new StorageCredential(accessKeyId, secretAccessKey, sessionToken)
      )
    );
  }

  /**
   * 请求图片内容安全检查并返回检查后的地址。
   *
   * @param url 已上传图片的远端地址。
   * @returns 通过安全检查后的图片地址。
   */
  private async checkImage(url: string): Promise<string> {
    const body: Record<string, string> = { 'url': url };
    const value = await this.apiService.post<Object>(
      '/cos/image/check',
      body
    );

    const record: Record<string, Object> = this.toRecord(
      value,
      'Invalid image safety check payload'
    );
    const safe: Object | undefined = record['safe'];

    if (typeof safe !== 'boolean') {
      throw new XmaxError(XmaxErrorCode.API_ERROR, 'Invalid image safety check payload');
    }

    if (!safe) {
      throw new XmaxError(XmaxErrorCode.UNSAFE_IMAGE, 'The image did not pass the safety check');
    }

    const checkedUrl: string = this.readString(record, 'url');
    if (!this.isHttpUrl(checkedUrl)) {
      throw new XmaxError(XmaxErrorCode.API_ERROR, 'Invalid image safety check payload');
    }

    return checkedUrl;
  }

  /**
   * 校验上传源、文件名和内容类型，并生成安全文件名。
   *
   * @param source 文件二进制数据或本地路径。
   * @param fileName 原始文件名称。
   * @param contentType 文件内容类型。
   * @param mediaType 文件媒体类型。
   * @returns 清理后的安全文件名。
   */
  private validateUpload(
    source: ArrayBuffer | string,
    fileName: string,
    contentType: string,
    mediaType: StorageMediaType
  ): string {
    if (typeof source === 'string') {
      try {
        if (!fileIo.accessSync(source) || !fileIo.statSync(source).isFile()) {
          throw new Error('not a file');
        }
      } catch (_error) {
        throw new XmaxError(
          XmaxErrorCode.INVALID_CONFIGURATION,
          `${this.capitalized(mediaType)} file path must reference an existing file`
        );
      }
    } else if (source.byteLength === 0) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        `${this.capitalized(mediaType)} data cannot be empty`
      );
    }

    if (!contentType.trim().toLowerCase().startsWith(`${mediaType}/`)) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        `${this.capitalized(mediaType)} content type must begin with ${mediaType}/`
      );
    }

    const safeName: string = this.sanitizeFileName(fileName);
    if (safeName.length === 0) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        `${this.capitalized(mediaType)} file name cannot be empty`
      );
    }

    return safeName;
  }

  /**
   * 校验下载地址和本地目标路径。
   *
   * @param remoteUrl 远端文件地址。
   * @param destinationPath 本地目标路径。
   * @returns 无返回值。
   */
  private validateDownload(
    remoteUrl: string,
    destinationPath: string
  ): void {
    if (!this.isHttpUrl(remoteUrl.trim())) {
      throw new XmaxError(XmaxErrorCode.INVALID_CONFIGURATION, 'Invalid download URL');
    }

    if (destinationPath.trim().length === 0) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Download destination path cannot be empty'
      );
    }
  }

  /**
   * 根据图片文件扩展名推断内容类型。
   *
   * @param fileName 图片文件名称。
   * @returns 推断出的图片内容类型。
   */
  private inferImageContentType(fileName: string): string {
    const types: Record<string, string> = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'jpe': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'heic': 'image/heic',
      'heif': 'image/heif',
      'bmp': 'image/bmp',
      'svg': 'image/svg+xml',
      'tif': 'image/tiff',
      'tiff': 'image/tiff',
      'avif': 'image/avif'
    };
    return this.inferContentType(fileName, types, 'image');
  }

  /**
   * 根据视频文件扩展名推断内容类型。
   *
   * @param fileName 视频文件名称。
   * @returns 推断出的视频内容类型。
   */
  private inferVideoContentType(fileName: string): string {
    const types: Record<string, string> = {
      'mp4': 'video/mp4',
      'mov': 'video/quicktime',
      'm4v': 'video/x-m4v',
      'webm': 'video/webm',
      'avi': 'video/x-msvideo',
      'mkv': 'video/x-matroska',
      '3gp': 'video/3gpp',
      '3g2': 'video/3gpp2',
      'ts': 'video/mp2t'
    };
    return this.inferContentType(fileName, types, 'video');
  }

  /**
   * 使用扩展名映射表推断文件内容类型。
   *
   * @param fileName 文件名称。
   * @param types 扩展名与内容类型的映射表。
   * @param mediaType 用于错误信息的媒体类型名称。
   * @returns 推断出的文件内容类型。
   */
  private inferContentType(
    fileName: string,
    types: Record<string, string>,
    mediaType: string
  ): string {
    const dotIndex: number = fileName.lastIndexOf('.');
    const extension: string = dotIndex < 0 ?
      '' : fileName.substring(dotIndex + 1).toLowerCase();
    const contentType: string | undefined = types[extension];
    if (contentType === undefined) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        `Unable to infer ${mediaType} content type from file extension`
      );
    }
    return contentType;
  }

  /**
   * 清理文件名中的不安全字符和首尾分隔符。
   *
   * @param value 原始文件名称。
   * @returns 可用于对象存储路径的安全文件名。
   */
  private sanitizeFileName(value: string): string {
    let result: string = value.trim()
      .replace(/[^\p{L}\p{N}._-]/gu, '_')
      .replace(/__/g, '_');
    while (result.length > 0 && this.isTrimFileNameCharacter(result.charAt(0))) {
      result = result.substring(1);
    }

    while (result.length > 0 &&
      this.isTrimFileNameCharacter(result.charAt(result.length - 1))) {
      result = result.substring(0, result.length - 1);
    }

    return result;
  }

  /**
   * 判断字符是否需要从文件名首尾移除。
   *
   * @param value 待检查字符。
   * @returns 字符需要移除时返回 true，否则返回 false。
   */
  private isTrimFileNameCharacter(value: string): boolean {
    return value === '.' || value === '_' || value === '-';
  }

  /**
   * 从本地路径中提取文件名称。
   *
   * @param filePath 本地文件路径。
   * @returns 路径中的最后一个文件名部分。
   */
  private lastPathComponent(filePath: string): string {
    const normalized: string = filePath.replace(/\\/g, '/').replace(/\/+$/, '');
    const slashIndex: number = normalized.lastIndexOf('/');
    return slashIndex < 0 ? normalized : normalized.substring(slashIndex + 1);
  }

  /**
   * 使用路径前缀、时间和随机标识生成唯一对象键。
   *
   * @param prefix 对象路径前缀。
   * @param fileName 安全文件名。
   * @returns 唯一对象键。
   */
  private makeObjectKey(
    prefix: string,
    fileName: string
  ): string {
    const uuid: string = util.generateRandomUUID(true).toLowerCase();
    return `${prefix}${Date.now()}_${uuid}_${fileName}`;
  }

  /**
   * 将未知 API 数据转换为可读取的记录。
   *
   * @param value 待转换的数据。
   * @param message 数据无效时使用的错误信息。
   * @returns 转换后的数据记录。
   */
  private toRecord(
    value: Object | undefined,
    message: string
  ): Record<string, Object> {
    if (value === undefined || value === null || typeof value !== 'object') {
      throw new XmaxError(XmaxErrorCode.API_ERROR, message);
    }
    return JSON.parse(JSON.stringify(value)) as Record<string, Object>;
  }

  /**
   * 读取并清理记录中的字符串字段。
   *
   * @param record 数据记录。
   * @param key 字段名称。
   * @returns 清理后的字符串；字段无效时返回空字符串。
   */
  private readString(
    record: Record<string, Object>,
    key: string
  ): string {
    const value: Object | undefined = record[key];
    return typeof value === 'string' ? value.trim() : '';
  }

  /**
   * 读取记录中的必填字符串字段。
   *
   * @param record 数据记录。
   * @param key 字段名称。
   * @param message 字段无效时使用的错误信息。
   * @returns 清理后的必填字符串。
   */
  private requiredString(
    record: Record<string, Object>,
    key: string,
    message: string
  ): string {
    const value: Object | undefined = record[key];
    if (typeof value !== 'string') {
      throw new XmaxError(XmaxErrorCode.API_ERROR, message);
    }
    return value.trim();
  }

  /**
   * 判断字符串是否为包含主机名的 HTTP 或 HTTPS 地址。
   *
   * @param value 待检查的地址。
   * @returns 地址有效时返回 true，否则返回 false。
   */
  private isHttpUrl(value: string): boolean {
    try {
      const parsed = new uri.URI(value);
      const scheme: string = parsed.scheme.toLowerCase();
      return (scheme === 'https' || scheme === 'http') && parsed.host.trim().length > 0;
    } catch (_error) {
      return false;
    }
  }

  /**
   * 将字符串首字母转换为大写。
   *
   * @param value 待转换字符串。
   * @returns 首字母大写后的字符串。
   */
  private capitalized(value: string): string {
    return value.charAt(0).toUpperCase() + value.substring(1);
  }
}
