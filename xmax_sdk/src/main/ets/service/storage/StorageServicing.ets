import { DownloadedFile } from '../../foundation/storage/DownloadedFile';
import { StorageProgressListener } from '../../foundation/storage/StorageProgressListener';
import { StoredFile } from '../../foundation/storage/StoredFile';

/** 定义图片和视频的上传、下载及图片安全检查能力。 */
export interface StorageServicing {

  /**
   * 上传图片数据。
   *
   * @param data 图片二进制数据。
   * @param fileName 文件名称。
   * @param contentType 内容类型。
   * @param progress 上传进度回调。
   * @returns 上传后的文件信息。
   */
  uploadImage(
    data: ArrayBuffer,
    fileName: string,
    contentType: string,
    progress?: StorageProgressListener
  ): Promise<StoredFile>;

  /**
   * 上传本地图片文件。
   *
   * @param filePath 本地文件路径。
   * @param contentType 内容类型。
   * @param progress 上传进度回调。
   * @returns 上传后的文件信息。
   */
  uploadImageFile(
    filePath: string,
    contentType?: string,
    progress?: StorageProgressListener
  ): Promise<StoredFile>;

  /**
   * 上传图片数据并执行内容安全检查。
   *
   * @param data 图片二进制数据。
   * @param fileName 文件名称。
   * @param contentType 内容类型。
   * @param progress 上传进度回调。
   * @returns 上传并通过安全检查后的文件信息。
   */
  uploadImageWithSafetyCheck(
    data: ArrayBuffer,
    fileName: string,
    contentType: string,
    progress?: StorageProgressListener
  ): Promise<StoredFile>;

  /**
   * 上传本地图片文件并执行内容安全检查。
   *
   * @param filePath 本地文件路径。
   * @param contentType 内容类型。
   * @param progress 上传进度回调。
   * @returns 上传并通过安全检查后的文件信息。
   */
  uploadImageFileWithSafetyCheck(
    filePath: string,
    contentType?: string,
    progress?: StorageProgressListener
  ): Promise<StoredFile>;

  /**
   * 上传视频数据。
   *
   * @param data 视频二进制数据。
   * @param fileName 文件名称。
   * @param contentType 内容类型。
   * @param progress 上传进度回调。
   * @returns 上传后的文件信息。
   */
  uploadVideo(
    data: ArrayBuffer,
    fileName: string,
    contentType: string,
    progress?: StorageProgressListener
  ): Promise<StoredFile>;

  /**
   * 上传本地视频文件。
   *
   * @param filePath 本地文件路径。
   * @param contentType 内容类型。
   * @param progress 上传进度回调。
   * @returns 上传后的文件信息。
   */
  uploadVideoFile(
    filePath: string,
    contentType?: string,
    progress?: StorageProgressListener
  ): Promise<StoredFile>;

  /**
   * 下载图片到本地文件。
   *
   * @param remoteUrl 远端图片地址。
   * @param destinationPath 本地目标路径。
   * @param progress 下载进度回调。
   * @returns 下载后的文件信息。
   */
  downloadImage(
    remoteUrl: string,
    destinationPath: string,
    progress?: StorageProgressListener
  ): Promise<DownloadedFile>;

  /**
   * 下载视频到本地文件。
   *
   * @param remoteUrl 远端视频地址。
   * @param destinationPath 本地目标路径。
   * @param progress 下载进度回调。
   * @returns 下载后的文件信息。
   */
  downloadVideo(
    remoteUrl: string,
    destinationPath: string,
    progress?: StorageProgressListener
  ): Promise<DownloadedFile>;
}
