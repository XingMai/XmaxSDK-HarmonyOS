//
//  StorageManaging.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { DownloadedFile } from './DownloadedFile';
import { StorageConfiguration } from './StorageConfiguration';
import { StorageProgressListener } from './StorageProgressListener';
import { StoredFile } from './StoredFile';

/** An interface for file uploads and downloads. */
export interface StorageManaging {

  /**
   * Uploads encoded data or a local file to storage.
   *
   * @param source The file bytes or local path.
   * @param objectKey The storage object key.
   * @param contentType The content MIME type.
   * @param configuration The storage configuration.
   * @param progress The upload progress callback.
   *
   * @returns The uploaded file information.
   */
  upload(
    source: ArrayBuffer | string,
    objectKey: string,
    contentType: string,
    configuration: StorageConfiguration,
    progress?: StorageProgressListener
  ): Promise<StoredFile>;

  /**
   * Downloads a remote file to a local path.
   *
   * @param remoteUrl The remote file URL.
   * @param destinationPath The destination file path.
   * @param progress The download progress callback.
   *
   * @returns The downloaded file information.
   */
  download(
    remoteUrl: string,
    destinationPath: string,
    progress?: StorageProgressListener
  ): Promise<DownloadedFile>;
}
