//
//  StorageServicing.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { DownloadedFile } from '../../foundation/storage/DownloadedFile';
import { StorageProgressListener } from '../../foundation/storage/StorageProgressListener';
import { StoredFile } from '../../foundation/storage/StoredFile';

/** An interface for image/video transfers and image content checks. */
export interface StorageServicing {

  /**
   * Uploads encoded image data.
   *
   * @param data The encoded image bytes.
   * @param fileName The filename.
   * @param contentType The content MIME type.
   * @param progress The upload progress callback.
   *
   * @returns The uploaded file information.
   */
  uploadImage(
    data: ArrayBuffer,
    fileName: string,
    contentType: string,
    progress?: StorageProgressListener
  ): Promise<StoredFile>;

  /**
   * Uploads a local image file.
   *
   * @param filePath The local file path.
   * @param contentType The content MIME type.
   * @param progress The upload progress callback.
   *
   * @returns The uploaded file information.
   */
  uploadImageFile(
    filePath: string,
    contentType?: string,
    progress?: StorageProgressListener
  ): Promise<StoredFile>;

  /**
   * Uploads encoded image data and checks its content.
   *
   * @param data The encoded image bytes.
   * @param fileName The filename.
   * @param contentType The content MIME type.
   * @param progress The upload progress callback.
   *
   * @returns The uploaded file after a successful safety check.
   */
  uploadImageWithSafetyCheck(
    data: ArrayBuffer,
    fileName: string,
    contentType: string,
    progress?: StorageProgressListener
  ): Promise<StoredFile>;

  /**
   * Uploads a local image file and checks its content.
   *
   * @param filePath The local file path.
   * @param contentType The content MIME type.
   * @param progress The upload progress callback.
   *
   * @returns The uploaded file after a successful safety check.
   */
  uploadImageFileWithSafetyCheck(
    filePath: string,
    contentType?: string,
    progress?: StorageProgressListener
  ): Promise<StoredFile>;

  /**
   * Uploads encoded video data.
   *
   * @param data The encoded video bytes.
   * @param fileName The filename.
   * @param contentType The content MIME type.
   * @param progress The upload progress callback.
   *
   * @returns The uploaded file information.
   */
  uploadVideo(
    data: ArrayBuffer,
    fileName: string,
    contentType: string,
    progress?: StorageProgressListener
  ): Promise<StoredFile>;

  /**
   * Uploads a local video file.
   *
   * @param filePath The local file path.
   * @param contentType The content MIME type.
   * @param progress The upload progress callback.
   *
   * @returns The uploaded file information.
   */
  uploadVideoFile(
    filePath: string,
    contentType?: string,
    progress?: StorageProgressListener
  ): Promise<StoredFile>;

  /**
   * Downloads an image to a local file.
   *
   * @param remoteUrl The remote image URL.
   * @param destinationPath The destination file path.
   * @param progress The download progress callback.
   *
   * @returns The downloaded file information.
   */
  downloadImage(
    remoteUrl: string,
    destinationPath: string,
    progress?: StorageProgressListener
  ): Promise<DownloadedFile>;

  /**
   * Downloads a video to a local file.
   *
   * @param remoteUrl The remote video URL.
   * @param destinationPath The destination file path.
   * @param progress The download progress callback.
   *
   * @returns The downloaded file information.
   */
  downloadVideo(
    remoteUrl: string,
    destinationPath: string,
    progress?: StorageProgressListener
  ): Promise<DownloadedFile>;
}
