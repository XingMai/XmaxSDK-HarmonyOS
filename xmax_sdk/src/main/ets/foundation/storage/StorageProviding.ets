import { DownloadedFile } from './DownloadedFile';
import { StorageConfiguration } from './StorageConfiguration';
import { StorageProgressListener } from './StorageProgressListener';
import { StoredFile } from './StoredFile';

/** 定义基础文件上传和下载能力。 */
export interface StorageProviding {

  /**
   * 上传二进制数据或本地文件到存储服务。
   *
   * @param source 文件二进制数据或本地文件路径。
   * @param objectKey 存储对象标识。
   * @param contentType 内容类型。
   * @param configuration 存储配置。
   * @param progress 上传进度回调。
   * @returns 上传后的文件信息。
   */
  upload(
    source: ArrayBuffer | string,
    objectKey: string,
    contentType: string,
    configuration: StorageConfiguration,
    progress?: StorageProgressListener
  ): Promise<StoredFile>;

  /**
   * 下载远端文件到本地路径。
   *
   * @param remoteUrl 远端文件地址。
   * @param destinationPath 本地目标路径。
   * @param progress 下载进度回调。
   * @returns 下载后的文件信息。
   */
  download(
    remoteUrl: string,
    destinationPath: string,
    progress?: StorageProgressListener
  ): Promise<DownloadedFile>;
}
