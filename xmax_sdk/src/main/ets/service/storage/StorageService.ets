//
//  StorageService.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

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

/** Temporary upload configuration and object path prefix. */
class TemporaryStorageConfiguration {

  // Upload path and access configuration

  /** The storage object path prefix. */
  readonly prefix: string;

  /** The configuration for the current operation. */
  readonly configuration: StorageConfiguration;

  /** Creates a temporary storage configuration. */
  constructor(
    prefix: string,
    configuration: StorageConfiguration
  ) {
    this.prefix = prefix;
    this.configuration = configuration;
  }
}

/** A media type supported by storage operations. */
enum StorageMediaType {

  /** Local image input. */
  IMAGE = 'image',

  /** Local video file input. */
  VIDEO = 'video'
}

/** Coordinates image/video transfers, temporary credentials, and image content checks. */
export class StorageService implements StorageServicing {

  // Upload credential and file operation dependencies

  /** The service sending authenticated Xmax API requests. */
  private readonly apiService: ApiServicing;

  // Foundation components

  /** The platform adapter for file uploads and downloads. */
  private readonly storageManager: StorageManaging;

  /** Creates a storage service. */
  constructor(
    apiService: ApiServicing,
    storageManager: StorageManaging
  ) {
    this.apiService = apiService;
    this.storageManager = storageManager;
  }

  /**
   * Uploads encoded image bytes.
   *
   * @param data The encoded image bytes.
   * @param fileName The filename.
   * @param contentType The image MIME type.
   * @param progress The upload progress handler.
   *
   * @returns The uploaded file information.
   */
  async uploadImage(
    data: ArrayBuffer,
    fileName: string,
    contentType: string,
    progress?: StorageProgressListener
  ): Promise<StoredFile> {
    return this.upload(
      data,
      fileName,
      contentType,
      StorageMediaType.IMAGE,
      false,
      progress
    );
  }

  /**
   * Uploads a local image file.
   *
   * @param filePath The local image file path.
   * @param contentType The image MIME type, inferred from the extension if omitted.
   * @param progress The upload progress handler.
   *
   * @returns The uploaded file information.
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
   * Uploads encoded image bytes and checks their content.
   *
   * @param data The encoded image bytes.
   * @param fileName The filename.
   * @param contentType The image MIME type.
   * @param progress The upload progress handler.
   *
   * @returns The uploaded file after a successful safety check.
   */
  async uploadImageWithSafetyCheck(
    data: ArrayBuffer,
    fileName: string,
    contentType: string,
    progress?: StorageProgressListener
  ): Promise<StoredFile> {
    return this.upload(
      data,
      fileName,
      contentType,
      StorageMediaType.IMAGE,
      true,
      progress
    );
  }

  /**
   * Uploads a local image file and checks its content.
   *
   * @param filePath The local image file path.
   * @param contentType The image MIME type, inferred from the extension if omitted.
   * @param progress The upload progress handler.
   *
   * @returns The uploaded file after a successful safety check.
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
   * Uploads encoded video bytes.
   *
   * @param data The encoded video bytes.
   * @param fileName The filename.
   * @param contentType The video MIME type.
   * @param progress The upload progress handler.
   *
   * @returns The uploaded file information.
   */
  async uploadVideo(
    data: ArrayBuffer,
    fileName: string,
    contentType: string,
    progress?: StorageProgressListener
  ): Promise<StoredFile> {
    return this.upload(
      data,
      fileName,
      contentType,
      StorageMediaType.VIDEO,
      false,
      progress
    );
  }

  /**
   * Uploads a local video file.
   *
   * @param filePath The local video file path.
   * @param contentType The video MIME type, inferred from the extension if omitted.
   * @param progress The upload progress handler.
   *
   * @returns The uploaded file information.
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
   * Downloads a remote image to a local file.
   *
   * @param remoteUrl The remote image URL.
   * @param destinationPath The destination file path.
   * @param progress The download progress handler.
   *
   * @returns The downloaded file information.
   */
  async downloadImage(
    remoteUrl: string,
    destinationPath: string,
    progress?: StorageProgressListener
  ): Promise<DownloadedFile> {
    this.validateDownload(
      remoteUrl,
      destinationPath
    );
    return this.storageManager.download(
      remoteUrl,
      destinationPath,
      progress
    );
  }

  /**
   * Downloads a remote video to a local file.
   *
   * @param remoteUrl The remote video URL.
   * @param destinationPath The destination file path.
   * @param progress The download progress handler.
   *
   * @returns The downloaded file information.
   */
  async downloadVideo(
    remoteUrl: string,
    destinationPath: string,
    progress?: StorageProgressListener
  ): Promise<DownloadedFile> {
    this.validateDownload(
      remoteUrl,
      destinationPath
    );
    return this.storageManager.download(
      remoteUrl,
      destinationPath,
      progress
    );
  }

  /**
   * Runs the shared upload flow with optional image content checking.
   *
   * @param source The file bytes or local path.
   * @param fileName The filename.
   * @param contentType The file MIME type.
   * @param mediaType The file media type.
   * @param checksSafety Whether to check image content safety.
   * @param progress The upload progress handler.
   *
   * @returns The uploaded file information.
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
      const resolution: string = await this.readResolution(
        source,
        mediaType
      );
      XmaxLogger.info(
        "开始上传 (Upload Started)\n" +
        `${XmaxLogger.localized("├─ 类型：", "├─ Type: ")}${mediaType}\n` +
        `${XmaxLogger.localized("├─ 分辨率：", "├─ Resolution: ")}${resolution}\n` +
        `${XmaxLogger.localized("├─ 大小：", "├─ Size: ")}${this.formatByteCount(byteCount)}\n` +
        `${XmaxLogger.localized("└─ 安全检测：", "└─ Safety Check: ")}${checksSafety}`,
        'Storage'
      );

      const temporary: TemporaryStorageConfiguration =
        await this.fetchStorageConfiguration();
      const objectKey: string = this.makeObjectKey(
        temporary.prefix,
        safeName
      );

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
        result = new StoredFile(
          checkedUrl,
          stored.objectKey,
          stored.etag
        );
      }

      XmaxLogger.info(
        "上传完成 (Upload Completed)\n" +
        `${XmaxLogger.localized("├─ 地址：", "├─ URL: ")}${result.url}\n` +
        `${XmaxLogger.localized("└─ 耗时：", "└─ Duration: ")}${this.formatDuration(Date.now() - startedAt)}`,
        'Storage'
      );
      return result;
    } catch (error) {
      if (!(error instanceof XmaxError && error.code === XmaxErrorCode.UPLOAD_ERROR)) {
        XmaxLogger.error(
          "上传失败 (Upload Failed)\n" +
          `${XmaxLogger.localized("├─ 错误码：", "├─ Error Code: ")}${this.errorCode(error)}\n` +
          `${XmaxLogger.localized("├─ 原因：", "├─ Reason: ")}${this.errorMessage(error)}\n` +
          `${XmaxLogger.localized("└─ 耗时：", "└─ Duration: ")}${this.formatDuration(Date.now() - startedAt)}`,
          'Storage'
        );
      }
      if (error instanceof Error) {
        throw error;
      }
      throw new XmaxError(
        XmaxErrorCode.UPLOAD_ERROR,
        String(error)
      );
    }
  }

  /**
   * Returns the upload source byte count.
   *
   * @param source The file bytes or local path.
   *
   * @returns The upload source byte count.
   */
  private sourceByteCount(
    source: ArrayBuffer | string
  ): number {
    return typeof source === 'string' ? fileIo.statSync(source).size : source.byteLength;
  }

  /**
   * Attempts to read uploaded media display dimensions.
   *
   * @param source The file bytes or local path.
   * @param mediaType The file media type.
   *
   * @returns The formatted resolution, or a placeholder if unavailable.
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
   * Reads image upload dimensions.
   *
   * @param source The image bytes or local path.
   *
   * @returns The formatted image resolution.
   */
  private async readImageResolution(
    source: ArrayBuffer | string
  ): Promise<string> {
    const imageSource: image.ImageSource = typeof source === 'string' ?
      image.createImageSource(source) : image.createImageSource(source);
    try {
      const info: image.ImageInfo = await imageSource.getImageInfo();
      return this.formatResolution(
        info.size.width,
        info.size.height
      );
    } finally {
      await imageSource.release();
    }
  }

  /**
   * Reads local video display dimensions accounting for rotation.
   *
   * @param source The video bytes or local path.
   *
   * @returns The formatted resolution, or a placeholder if binary input cannot be read.
   */
  private async readVideoResolution(
    source: ArrayBuffer | string
  ): Promise<string> {
    if (typeof source !== 'string') {
      return '--';
    }

    const sourceFile: fileIo.File = fileIo.openSync(
      source,
      fileIo.OpenMode.READ_ONLY
    );
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
        this.formatResolution(
          height,
          width
        ) :
        this.formatResolution(
          width,
          height
        );
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
   * Formats valid dimensions as a resolution.
   *
   * @param width The media width.
   * @param height The media height.
   *
   * @returns The formatted resolution, or a placeholder for invalid dimensions.
   */
  private formatResolution(
    width: number,
    height: number
  ): string {
    if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) {
      return '--';
    }
    return `${width} × ${height}`;
  }

  /**
   * Formats a byte count as a readable file size.
   *
   * @param byteCount The file byte count.
   *
   * @returns The formatted file size.
   */
  private formatByteCount(
    byteCount: number
  ): string {
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

  /**
   * Returns the SDK code for an upload error.
   *
   * @param error The upload error.
   *
   * @returns The SDK error code.
   */
  private errorCode(
    error: Object
  ): string {
    return error instanceof XmaxError ? error.code : XmaxErrorCode.UPLOAD_ERROR;
  }

  /**
   * Returns a readable upload error.
   *
   * @param error The upload error.
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
   * Requests and parses temporary upload configuration.
   *
   * @returns The temporary storage configuration.
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
      throw new XmaxError(
        XmaxErrorCode.API_ERROR,
        'Invalid storage credential payload'
      );
    }

    return new TemporaryStorageConfiguration(
      prefix,
      new StorageConfiguration(
        bucket,
        region,
        endpoint,
        new StorageCredential(
          accessKeyId,
          secretAccessKey,
          sessionToken
        )
      )
    );
  }

  /**
   * Requests an image content check and returns the approved URL.
   *
   * @param url The uploaded image URL.
   *
   * @returns The image URL after the content check.
   */
  private async checkImage(
    url: string
  ): Promise<string> {
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
      throw new XmaxError(
        XmaxErrorCode.API_ERROR,
        'Invalid image safety check payload'
      );
    }

    if (!safe) {
      throw new XmaxError(
        XmaxErrorCode.UNSAFE_IMAGE,
        'The image did not pass the safety check'
      );
    }

    const checkedUrl: string = this.readString(
      record,
      'url'
    );
    if (!this.isHttpUrl(checkedUrl)) {
      throw new XmaxError(
        XmaxErrorCode.API_ERROR,
        'Invalid image safety check payload'
      );
    }

    return checkedUrl;
  }

  /**
   * Validates upload input, filename, and MIME type, producing a safe filename.
   *
   * @param source The file bytes or local path.
   * @param fileName The original filename.
   * @param contentType The file MIME type.
   * @param mediaType The file media type.
   *
   * @returns The sanitized filename.
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
   * Validates a download URL and destination path.
   *
   * @param remoteUrl The remote file URL.
   * @param destinationPath The destination file path.
   */
  private validateDownload(
    remoteUrl: string,
    destinationPath: string
  ): void {
    if (!this.isHttpUrl(remoteUrl.trim())) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Invalid download URL'
      );
    }

    if (destinationPath.trim().length === 0) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Download destination path cannot be empty'
      );
    }
  }

  /**
   * Infers image MIME type from its extension.
   *
   * @param fileName The image filename.
   *
   * @returns The inferred image MIME type.
   */
  private inferImageContentType(
    fileName: string
  ): string {
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
    return this.inferContentType(
      fileName,
      types,
      'image'
    );
  }

  /**
   * Infers video MIME type from its extension.
   *
   * @param fileName The video filename.
   *
   * @returns The inferred video MIME type.
   */
  private inferVideoContentType(
    fileName: string
  ): string {
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
    return this.inferContentType(
      fileName,
      types,
      'video'
    );
  }

  /**
   * Infers MIME type using an extension map.
   *
   * @param fileName The filename.
   * @param types The extension-to-MIME-type map.
   * @param mediaType The media type name for error messages.
   *
   * @returns The inferred MIME type.
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
   * Removes unsafe filename characters and leading or trailing separators.
   *
   * @param value The original filename.
   *
   * @returns The safe filename for object storage paths.
   */
  private sanitizeFileName(
    value: string
  ): string {
    let result: string = value.trim()
      .replace(
        /[^\p{L}\p{N}._-]/gu,
        '_'
      )
      .replace(
        /__/g,
        '_'
      );
    while (result.length > 0 && this.isTrimFileNameCharacter(result.charAt(0))) {
      result = result.substring(1);
    }

    while (result.length > 0 &&
      this.isTrimFileNameCharacter(result.charAt(result.length - 1))) {
      result = result.substring(
        0,
        result.length - 1
      );
    }

    return result;
  }

  /**
   * Checks whether a filename boundary character should be removed.
   *
   * @param value The character to check.
   *
   * @returns True if the character should be removed.
   */
  private isTrimFileNameCharacter(
    value: string
  ): boolean {
    return value === '.' || value === '_' || value === '-';
  }

  /**
   * Extracts the filename from a local path.
   *
   * @param filePath The local file path.
   *
   * @returns The final filename component.
   */
  private lastPathComponent(
    filePath: string
  ): string {
    const normalized: string = filePath.replace(
      /\\/g,
      '/'
    ).replace(
      /\/+$/,
      ''
    );
    const slashIndex: number = normalized.lastIndexOf('/');
    return slashIndex < 0 ? normalized : normalized.substring(slashIndex + 1);
  }

  /**
   * Creates a unique object key from prefix, time, and a random identity.
   *
   * @param prefix The object path prefix.
   * @param fileName The safe filename.
   *
   * @returns The unique object key.
   */
  private makeObjectKey(
    prefix: string,
    fileName: string
  ): string {
    const uuid: string = util.generateRandomUUID(true).toLowerCase();
    return `${prefix}${Date.now()}_${uuid}_${fileName}`;
  }

  /**
   * Converts unknown API data into a readable record.
   *
   * @param value The data to convert.
   * @param message The error message for invalid data.
   *
   * @returns The converted data record.
   */
  private toRecord(
    value: Object | undefined,
    message: string
  ): Record<string, Object> {
    if (value === undefined || value === null || typeof value !== 'object') {
      throw new XmaxError(
        XmaxErrorCode.API_ERROR,
        message
      );
    }
    return JSON.parse(JSON.stringify(value)) as Record<string, Object>;
  }

  /**
   * Reads and trims a string field.
   *
   * @param record The data record.
   * @param key The field name.
   *
   * @returns The trimmed string, or an empty string for invalid input.
   */
  private readString(
    record: Record<string, Object>,
    key: string
  ): string {
    const value: Object | undefined = record[key];
    return typeof value === 'string' ? value.trim() : '';
  }

  /**
   * Reads a required string field.
   *
   * @param record The data record.
   * @param key The field name.
   * @param message The error message for an invalid field.
   *
   * @returns The required trimmed string.
   */
  private requiredString(
    record: Record<string, Object>,
    key: string,
    message: string
  ): string {
    const value: Object | undefined = record[key];
    if (typeof value !== 'string') {
      throw new XmaxError(
        XmaxErrorCode.API_ERROR,
        message
      );
    }
    return value.trim();
  }

  /**
   * Checks for an HTTP or HTTPS URL with a hostname.
   *
   * @param value The URL to check.
   *
   * @returns True if the URL is valid.
   */
  private isHttpUrl(
    value: string
  ): boolean {
    try {
      const parsed = new uri.URI(value);
      const scheme: string = parsed.scheme.toLowerCase();
      return (scheme === 'https' || scheme === 'http') && parsed.host.trim().length > 0;
    } catch (_error) {
      return false;
    }
  }

  /**
   * Capitalizes the first character of a string.
   *
   * @param value The string to convert.
   *
   * @returns The string with its first character capitalized.
   */
  private capitalized(
    value: string
  ): string {
    return value.charAt(0).toUpperCase() + value.substring(1);
  }
}
