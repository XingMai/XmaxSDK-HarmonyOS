//
//  DownloadedFile.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/** 记录下载文件的本地路径和实际字节数。 */
export class DownloadedFile {

  /** 本地下载结果 */
  readonly filePath: string;
  readonly byteCount: number;

  /**
   * 创建下载文件信息。
   *
   * @param filePath 下载后的本地文件路径。
   * @param byteCount 下载文件的字节数。
   * @returns 新建的 DownloadedFile 实例。
   */
  constructor(
    filePath: string,
    byteCount: number
  ) {
    this.filePath = filePath;
    this.byteCount = byteCount;
  }
}
