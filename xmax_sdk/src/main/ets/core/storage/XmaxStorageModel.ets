/** 表示文件传输进度。 */
export class XmaxStorageProgress {

  /** 已传输的字节数。 */
  readonly completedBytes: number;

  /** 需要传输的总字节数。 */
  readonly totalBytes: number;

  /**
   * 创建文件传输进度。
   *
   * @param completedBytes 已传输的字节数。
   * @param totalBytes 需要传输的总字节数。
   */
  constructor(
    completedBytes: number,
    totalBytes: number
  ) {
    this.completedBytes = completedBytes;
    this.totalBytes = totalBytes;
  }

  /** @returns 限制在 `0` 至 `1` 范围内的传输完成比例。 */
  get fractionCompleted(): number {
    if (this.totalBytes <= 0) {
      return 0;
    }

    return Math.min(Math.max(this.completedBytes / this.totalBytes, 0), 1);
  }
}

/** 文件传输进度监听器。 */
export type XmaxStorageProgressListener = (progress: XmaxStorageProgress) => void;

/** 表示上传成功的文件。 */
export class XmaxUploadedFile {

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

  /** 下载后的本地文件路径。 */
  readonly filePath: string;

  /** 下载文件的字节数。 */
  readonly byteCount: number;

  /**
   * 创建下载文件信息。
   *
   * @param filePath 下载后的本地文件路径。
   * @param byteCount 下载文件的字节数。
   */
  constructor(
    filePath: string,
    byteCount: number
  ) {
    this.filePath = filePath;
    this.byteCount = byteCount;
  }
}
