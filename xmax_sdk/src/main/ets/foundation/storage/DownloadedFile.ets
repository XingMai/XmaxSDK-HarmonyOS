//
//  DownloadedFile.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/** A downloaded file's local path and actual byte count. */
export class DownloadedFile {

  /** The local media file path. */
  readonly filePath: string;

  /** The actual file length, in bytes. */
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
