//
//  XmaxStorageModel.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/** 表示文件传输进度。 */
export class XmaxStorageProgress {

  /** 字节传输进度 */
  /** 已传输的字节数。 */
  readonly completedBytes: number;

  /** 需要传输的总字节数。 */
  readonly totalBytes: number;

  /**
   * 创建文件传输进度。
   *
   * @param completedBytes 已传输的字节数。
   * @param totalBytes 需要传输的总字节数。
   * @returns 新建的 XmaxStorageProgress 实例。
   */
  constructor(
    completedBytes: number,
    totalBytes: number
  ) {
    this.completedBytes = completedBytes;
    this.totalBytes = totalBytes;
  }

  /**
   * 计算已完成字节数占总字节数的比例。
   *
   * @returns 0～1 的完成比例；总字节数无效时返回 0。
   */
  get fractionCompleted(): number {
    if (this.totalBytes <= 0) {
      return 0;
    }

    return Math.min(Math.max(this.completedBytes / this.totalBytes, 0), 1);
  }
}

/**
 * 文件传输进度监听器。
 *
 * @param progress 已完成与总字节数及其完成比例。
 * @returns 无返回值。
 */
export type XmaxStorageProgressListener = (progress: XmaxStorageProgress) => void;

/** 表示上传成功的文件。 */
export class XmaxUploadedFile {

  /** 上传对象信息 */
  /** 文件的远端访问地址。 */
  readonly url: string;

  /** 文件在存储服务中的对象标识。 */
  readonly objectKey: string;

  /** 存储服务返回的可选实体标识。 */
  readonly etag?: string;

  /**
   * 创建上传文件信息。
   *
   * @param url 文件的远端访问地址。
   * @param objectKey 文件在存储服务中的对象标识。
   * @param etag 存储服务返回的可选实体标识。
   * @returns 新建的 XmaxUploadedFile 实例。
   */
  constructor(
    url: string,
    objectKey: string,
    etag?: string
  ) {
    this.url = url;
    this.objectKey = objectKey;
    this.etag = etag;
  }
}

/** 表示下载成功的文件。 */
export class XmaxDownloadedFile {

  /** 本地下载结果 */
  /** 下载后的本地文件路径。 */
  readonly filePath: string;

  /** 下载文件的字节数。 */
  readonly byteCount: number;

  /**
   * 创建下载文件信息。
   *
   * @param filePath 下载后的本地文件路径。
   * @param byteCount 下载文件的字节数。
   * @returns 新建的 XmaxDownloadedFile 实例。
   */
  constructor(
    filePath: string,
    byteCount: number
  ) {
    this.filePath = filePath;
    this.byteCount = byteCount;
  }
}
