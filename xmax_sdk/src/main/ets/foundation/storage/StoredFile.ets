//
//  StoredFile.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/** 记录已上传对象的访问地址、对象键和 ETag。 */
export class StoredFile {

  /** 上传对象信息 */
  readonly url: string;
  readonly objectKey: string;
  readonly etag?: string;

  /**
   * 创建上传文件信息。
   *
   * @param url 文件的远端访问地址。
   * @param objectKey 文件在存储服务中的对象标识。
   * @param etag 存储服务返回的可选实体标识。
   * @returns 新建的 StoredFile 实例。
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
