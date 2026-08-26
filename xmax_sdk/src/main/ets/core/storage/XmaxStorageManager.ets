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

/** 文件存储公共入口，负责将服务层模型转换为对外公开模型。 */
export class XmaxStorageManager implements XmaxStorageManaging {

  // 服务层组件
  private readonly storageService: StorageServicing;

  /**
   * 创建文件存储 Manager。
   *
   * @param context 访问本地文件和存储平台能力所需的应用上下文。
   * @param apiService 获取上传配置等服务端数据的网络服务。
   */
  constructor(
    context: common.Context,
    apiService: ApiServicing
  ) {
    // 服务层组件
    this.storageService = new StorageService(
      apiService,
      new StorageManager(context)
    );
  }

  /**
   * 上传图片数据。
   *
   * @param data 图片二进制数据。
   * @param fileName 文件名称。
   * @param contentType 图片内容类型。
   * @param progress 可选的传输进度监听器。
   * @returns 上传成功后的公开文件信息。
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
   * 上传本地图片文件。
   *
   * @param filePath 本地图片文件路径。
   * @param contentType 可选的图片内容类型；未传入时由服务层推断。
   * @param progress 可选的传输进度监听器。
   * @returns 上传成功后的公开文件信息。
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
   * 上传图片数据并执行内容安全检查。
   *
   * @param data 图片二进制数据。
   * @param fileName 文件名称。
   * @param contentType 图片内容类型。
   * @param progress 可选的传输进度监听器。
   * @returns 通过内容安全检查并上传成功后的公开文件信息。
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
   * 上传本地图片文件并执行内容安全检查。
   *
   * @param filePath 本地图片文件路径。
   * @param contentType 可选的图片内容类型；未传入时由服务层推断。
   * @param progress 可选的传输进度监听器。
   * @returns 通过内容安全检查并上传成功后的公开文件信息。
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
   * 上传视频数据。
   *
   * @param data 视频二进制数据。
   * @param fileName 文件名称。
   * @param contentType 视频内容类型。
   * @param progress 可选的传输进度监听器。
   * @returns 上传成功后的公开文件信息。
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
   * 上传本地视频文件。
   *
   * @param filePath 本地视频文件路径。
   * @param contentType 可选的视频内容类型；未传入时由服务层推断。
   * @param progress 可选的传输进度监听器。
   * @returns 上传成功后的公开文件信息。
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
   * 下载远端图片到指定本地路径。
   *
   * @param remoteUrl 远端图片地址。
   * @param destinationPath 本地目标路径。
   * @param progress 可选的传输进度监听器。
   * @returns 下载成功后的公开文件信息。
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
   * 下载远端视频到指定本地路径。
   *
   * @param remoteUrl 远端视频地址。
   * @param destinationPath 本地目标路径。
   * @param progress 可选的传输进度监听器。
   * @returns 下载成功后的公开文件信息。
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
   * 将公开进度监听器转换为服务层进度监听器。
   *
   * @param listener 可选的公开进度监听器。
   * @returns 服务层进度监听器；未传入监听器时返回空值。
   */
  private progressListener(
    listener?: XmaxStorageProgressListener
  ): StorageProgressListener | undefined {
    if (listener === undefined) {
      return undefined;
    }

    return (completedBytes: number, totalBytes: number): void => {
      listener(new XmaxStorageProgress(completedBytes, totalBytes));
    };
  }

  /**
   * 将服务层上传结果转换为公开上传文件模型。
   *
   * @param file 服务层上传结果。
   * @returns 对接入方公开的上传文件信息。
   */
  private toUploadedFile(file: StoredFile): XmaxUploadedFile {
    return new XmaxUploadedFile(file.url, file.objectKey, file.etag);
  }

  /**
   * 将服务层下载结果转换为公开下载文件模型。
   *
   * @param file 服务层下载结果。
   * @returns 对接入方公开的下载文件信息。
   */
  private toDownloadedFile(file: DownloadedFile): XmaxDownloadedFile {
    return new XmaxDownloadedFile(file.filePath, file.byteCount);
  }
}
