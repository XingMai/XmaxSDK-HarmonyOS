//
//  StorageCredential.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/** Temporary credentials authorizing storage access. Avoid logging their values. */
export class StorageCredential {

  /** The temporary storage access key identifier. */
  readonly accessKeyId: string;

  /** The temporary storage secret access key. */
  readonly secretAccessKey: string;

  /** The temporary storage session token. */
  readonly sessionToken: string;

  /** Creates temporary storage credentials. */
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
