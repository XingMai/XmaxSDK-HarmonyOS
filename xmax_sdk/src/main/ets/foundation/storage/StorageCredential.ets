//
//  StorageCredential.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/** 用于授权对象存储请求的临时访问凭证；应避免输出到日志。 */
export class StorageCredential {

  /** 临时访问凭证 */
  readonly accessKeyId: string;
  readonly secretAccessKey: string;
  readonly sessionToken: string;

  /**
   * 创建临时存储凭证。
   *
   * @param accessKeyId 临时访问密钥标识。
   * @param secretAccessKey 临时访问密钥；应避免输出到日志。
   * @param sessionToken 临时访问令牌。
   * @returns 新建的 StorageCredential 实例。
   */
  constructor(
    accessKeyId: string,
    secretAccessKey: string,
    sessionToken: string
  ) {
    this.accessKeyId = accessKeyId;
    this.secretAccessKey = secretAccessKey;
    this.sessionToken = sessionToken;
  }
}
