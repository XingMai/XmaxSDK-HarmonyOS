//
//  XmaxStorageModel.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/** The progress of a file transfer. */
export class XmaxStorageProgress {

  /** The number of transferred bytes. */
  readonly completedBytes: number;

  /** The total number of bytes to transfer. */
  readonly totalBytes: number;

  /** Creates file transfer progress. */
  constructor(
    completedBytes: number,
    totalBytes: number
  ) {
    this.completedBytes = completedBytes;
    this.totalBytes = totalBytes;
  }

  /** The transferred fraction of total bytes in 0 to 1, or zero for an invalid total. */
  get fractionCompleted(): number {
    if (this.totalBytes <= 0) {
      return 0;
    }

    return Math.min(Math.max(this.completedBytes / this.totalBytes, 0), 1);
  }
}

/**
 * A file transfer progress handler.
 *
 * @param progress The transferred and total byte counts and completion fraction.
 */
export type XmaxStorageProgressListener = (
  progress: XmaxStorageProgress
) => void;

/** A successfully uploaded file. */
export class XmaxUploadedFile {

  /** The remote file URL. */
  readonly url: string;

  /** The storage object key. */
  readonly objectKey: string;

  /** The optional entity tag returned by storage. */
  readonly etag?: string;

  /** Creates uploaded file information. */
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

/** A successfully downloaded file. */
export class XmaxDownloadedFile {

  /** The downloaded file path. */
  readonly filePath: string;

  /** The downloaded byte count. */
  readonly byteCount: number;

  /** Creates downloaded file information. */
  constructor(
    filePath: string,
    byteCount: number
  ) {
    this.filePath = filePath;
    this.byteCount = byteCount;
  }
}
