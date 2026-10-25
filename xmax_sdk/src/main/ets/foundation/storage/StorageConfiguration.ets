//
//  StorageConfiguration.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { StorageCredential } from './StorageCredential';

/** The region, endpoint, bucket, and temporary credentials for object storage. */
export class StorageConfiguration {

  /** The destination object storage bucket. */
  readonly bucket: string;

  /** The object storage region. */
  readonly region: string;

  /** The object storage endpoint. */
  readonly endpoint: string;

  /** The temporary credentials authorizing object storage access. */
  readonly credential: StorageCredential;

  /** Creates an object storage configuration. */
  constructor(
    bucket: string,
    region: string,
    endpoint: string,
    credential: StorageCredential
  ) {
    this.bucket = bucket;
    this.region = region;
    this.endpoint = endpoint;
    this.credential = credential;
  }
}
