//
//  StorageConfiguration.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { StorageCredential } from './StorageCredential';

/** 一次对象存储访问所需的区域、地址、存储桶和临时凭证。 */
export class StorageConfiguration {

  /** 对象存储目标 */
  readonly bucket: string;
  readonly region: string;
  readonly endpoint: string;

  /** 临时访问凭证 */
  readonly credential: StorageCredential;

  /**
   * 创建对象存储访问配置。
   *
   * @param bucket 对象存储桶名称。
   * @param region 对象存储服务区域。
   * @param endpoint 对象存储服务地址。
   * @param credential 授权对象存储访问的临时凭证。
   * @returns 新建的 StorageConfiguration 实例。
   */
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
