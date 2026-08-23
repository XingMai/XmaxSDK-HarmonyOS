import {
  XmaxDownloadedFile,
  XmaxStorageProgressListener,
  XmaxUploadedFile
} from './XmaxStorageModel';

/** 定义 SDK 对接入方提供的文件上传和下载能力。 */
export interface XmaxStorageManaging {

  /**
   * 上传图片数据。
   *
   * @param data 图片数据。
   * @param fileName 文件名称。
   * @param contentType 内容类型。
   * @param progress 文件传输进度监听器。
   * @returns 上传成功后的文件信息。
   */
  uploadImage(
    data: ArrayBuffer,
    fileName: string,
    contentType: string,
    progress?: XmaxStorageProgressListener
  ): Promise<XmaxUploadedFile>;

  /**
   * 上传本地图片文件。
   *
   * @param filePath 本地文件路径。
   * @param contentType 内容类型。
   * @param progress 文件传输进度监听器。
   * @returns 上传成功后的文件信息。
   */
  uploadImageFile(
    filePath: string,
    contentType?: string,
    progress?: XmaxStorageProgressListener
  ): Promise<XmaxUploadedFile>;

  /**
   * 上传图片数据并执行内容安全检查。
   *
   * @param data 图片数据。
   * @param fileName 文件名称。
   * @param contentType 内容类型。
   * @param progress 文件传输进度监听器。
   * @returns 上传成功后的文件信息。
   */
  uploadImageWithSafetyCheck(
    data: ArrayBuffer,
    fileName: string,
    contentType: string,
    progress?: XmaxStorageProgressListener
  ): Promise<XmaxUploadedFile>;

  /**
   * 上传本地图片文件并执行内容安全检查。
   *
   * @param filePath 本地文件路径。
   * @param contentType 内容类型。
   * @param progress 文件传输进度监听器。
   * @returns 上传成功后的文件信息。
   */
  uploadImageFileWithSafetyCheck(
    filePath: string,
    contentType?: string,
    progress?: XmaxStorageProgressListener
  ): Promise<XmaxUploadedFile>;

  /**
   * 上传视频数据。
   *
   * @param data 视频数据。
   * @param fileName 文件名称。
   * @param contentType 内容类型。
   * @param progress 文件传输进度监听器。
   * @returns 上传成功后的文件信息。
   */
  uploadVideo(
    data: ArrayBuffer,
    fileName: string,
    contentType: string,
    progress?: XmaxStorageProgressListener
  ): Promise<XmaxUploadedFile>;

  /**
   * 上传本地视频文件。
   *
   * @param filePath 本地文件路径。
   * @param contentType 内容类型。
   * @param progress 文件传输进度监听器。
   * @returns 上传成功后的文件信息。
   */
  uploadVideoFile(
    filePath: string,
    contentType?: string,
    progress?: XmaxStorageProgressListener
  ): Promise<XmaxUploadedFile>;

  /**
   * 下载图片到本地文件。
   *
   * @param remoteUrl 远端文件地址。
   * @param destinationPath 本地目标路径。
   * @param progress 文件传输进度监听器。
   * @returns 下载成功后的文件信息。
   */
  downloadImage(
    remoteUrl: string,
    destinationPath: string,
    progress?: XmaxStorageProgressListener
  ): Promise<XmaxDownloadedFile>;

  /**
   * 下载视频到本地文件。
   *
   * @param remoteUrl 远端文件地址。
   * @param destinationPath 本地目标路径。
   * @param progress 文件传输进度监听器。
   * @returns 下载成功后的文件信息。
   */
  downloadVideo(
    remoteUrl: string,
    destinationPath: string,
    progress?: XmaxStorageProgressListener
  ): Promise<XmaxDownloadedFile>;
}
