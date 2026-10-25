//
//  StoredFile.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/** An uploaded object's URL, key, and entity tag. */
export class StoredFile {

  /** The remote URL used to access the stored file. */
  readonly url: string;

  /** The uploaded object's storage key. */
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
