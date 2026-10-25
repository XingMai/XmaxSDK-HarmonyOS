//
//  XmaxStorageManager.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { common } from '@kit.AbilityKit';
import { DownloadedFile } from '../../foundation/storage/DownloadedFile';
import { StorageManager } from '../../foundation/storage/StorageManager';
import { StorageProgressListener } from '../../foundation/storage/StorageProgressListener';
import { StoredFile } from '../../foundation/storage/StoredFile';
import { ApiServicing } from '../../service/network/ApiServicing';
import { StorageService } from '../../service/storage/StorageService';
import { StorageServicing } from '../../service/storage/StorageServicing';
import { XmaxStorageManaging } from './XmaxStorageManaging';
import {
  XmaxDownloadedFile,
  XmaxStorageProgress,
  XmaxStorageProgressListener,
  XmaxUploadedFile
} from './XmaxStorageModel';

/** A storage manager converting service results into public file models. */
export class XmaxStorageManager implements XmaxStorageManaging {

  // Storage service dependencies

  /** The service coordinating transfers, credentials, and image checks. */
  private readonly storageService: StorageServicing;

  /**
   * Creates a storage manager.
   *
   * @param context The application context for local files and platform storage services.
   * @param apiService The network service retrieving upload configuration.
   */
  constructor(
    context: common.Context,
    apiService: ApiServicing
  ) {
    // Service components
    this.storageService = new StorageService(
      apiService,
      new StorageManager(context)
    );
  }

  /**
   * Uploads encoded image data.
   *
   * @param data The encoded image bytes.
   * @param fileName The filename.
   * @param contentType The image MIME type.
   * @param progress The optional transfer progress handler.
   *
   * @returns The public uploaded file information.
   */
  async uploadImage(
    data: ArrayBuffer,
    fileName: string,
    contentType: string,
    progress?: XmaxStorageProgressListener
  ): Promise<XmaxUploadedFile> {
    return this.toUploadedFile(await this.storageService.uploadImage(
      data,
      fileName,
      contentType,
      this.progressListener(progress)
    ));
  }

  /**
   * Uploads a local image file.
   *
   * @param filePath The local image file path.
   * @param contentType The image MIME type; inferred by the service if omitted.
   * @param progress The optional transfer progress handler.
   *
   * @returns The public uploaded file information.
   */
  async uploadImageFile(
    filePath: string,
    contentType?: string,
    progress?: XmaxStorageProgressListener
  ): Promise<XmaxUploadedFile> {
    return this.toUploadedFile(await this.storageService.uploadImageFile(
      filePath,
      contentType,
      this.progressListener(progress)
    ));
  }

  /**
   * Uploads encoded image data and checks its content.
   *
   * @param data The encoded image bytes.
   * @param fileName The filename.
   * @param contentType The image MIME type.
   * @param progress The optional transfer progress handler.
   *
   * @returns The uploaded file information after a successful content check.
   */
  async uploadImageWithSafetyCheck(
    data: ArrayBuffer,
    fileName: string,
    contentType: string,
    progress?: XmaxStorageProgressListener
  ): Promise<XmaxUploadedFile> {
    return this.toUploadedFile(await this.storageService.uploadImageWithSafetyCheck(
      data,
      fileName,
      contentType,
      this.progressListener(progress)
    ));
  }

  /**
   * Uploads a local image file and checks its content.
   *
   * @param filePath The local image file path.
   * @param contentType The image MIME type; inferred by the service if omitted.
   * @param progress The optional transfer progress handler.
   *
   * @returns The uploaded file information after a successful content check.
   */
  async uploadImageFileWithSafetyCheck(
    filePath: string,
    contentType?: string,
    progress?: XmaxStorageProgressListener
  ): Promise<XmaxUploadedFile> {
    return this.toUploadedFile(await this.storageService.uploadImageFileWithSafetyCheck(
      filePath,
      contentType,
      this.progressListener(progress)
    ));
  }

  /**
   * Uploads encoded video data.
   *
   * @param data The encoded video bytes.
   * @param fileName The filename.
   * @param contentType The video MIME type.
   * @param progress The optional transfer progress handler.
   *
   * @returns The public uploaded file information.
   */
  async uploadVideo(
    data: ArrayBuffer,
    fileName: string,
    contentType: string,
    progress?: XmaxStorageProgressListener
  ): Promise<XmaxUploadedFile> {
    return this.toUploadedFile(await this.storageService.uploadVideo(
      data,
      fileName,
      contentType,
      this.progressListener(progress)
    ));
  }

  /**
   * Uploads a local video file.
   *
   * @param filePath The local video file path.
   * @param contentType The video MIME type; inferred by the service if omitted.
   * @param progress The optional transfer progress handler.
   *
   * @returns The public uploaded file information.
   */
  async uploadVideoFile(
    filePath: string,
    contentType?: string,
    progress?: XmaxStorageProgressListener
  ): Promise<XmaxUploadedFile> {
    return this.toUploadedFile(await this.storageService.uploadVideoFile(
      filePath,
      contentType,
      this.progressListener(progress)
    ));
  }

  /**
   * Downloads a remote image to a local path.
   *
   * @param remoteUrl The remote image URL.
   * @param destinationPath The destination file path.
   * @param progress The optional transfer progress handler.
   *
   * @returns The public downloaded file information.
   */
  async downloadImage(
    remoteUrl: string,
    destinationPath: string,
    progress?: XmaxStorageProgressListener
  ): Promise<XmaxDownloadedFile> {
    return this.toDownloadedFile(await this.storageService.downloadImage(
      remoteUrl,
      destinationPath,
      this.progressListener(progress)
    ));
  }

  /**
   * Downloads a remote video to a local path.
   *
   * @param remoteUrl The remote video URL.
   * @param destinationPath The destination file path.
   * @param progress The optional transfer progress handler.
   *
   * @returns The public downloaded file information.
   */
  async downloadVideo(
    remoteUrl: string,
    destinationPath: string,
    progress?: XmaxStorageProgressListener
  ): Promise<XmaxDownloadedFile> {
    return this.toDownloadedFile(await this.storageService.downloadVideo(
      remoteUrl,
      destinationPath,
      this.progressListener(progress)
    ));
  }

  /**
   * Converts a public progress handler into a service handler.
   *
   * @param listener The optional public progress handler.
   *
   * @returns The service progress handler, or undefined if absent.
   */
  private progressListener(
    listener?: XmaxStorageProgressListener
  ): StorageProgressListener | undefined {
    if (listener === undefined) {
      return undefined;
    }

    return (completedBytes: number, totalBytes: number): void => {
      listener(new XmaxStorageProgress(
        completedBytes,
        totalBytes
      ));
    };
  }

  /**
   * Converts a service upload result into a public file model.
   *
   * @param file The service upload result.
   *
   * @returns The public uploaded file information.
   */
  private toUploadedFile(
    file: StoredFile
  ): XmaxUploadedFile {
    return new XmaxUploadedFile(
      file.url,
      file.objectKey,
      file.etag
    );
  }

  /**
   * Converts a service download result into a public file model.
   *
   * @param file The service download result.
   *
   * @returns The public downloaded file information.
   */
  private toDownloadedFile(
    file: DownloadedFile
  ): XmaxDownloadedFile {
    return new XmaxDownloadedFile(
      file.filePath,
      file.byteCount
    );
  }
}
