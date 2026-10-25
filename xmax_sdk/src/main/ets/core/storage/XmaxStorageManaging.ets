//
//  XmaxStorageManaging.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import {
  XmaxDownloadedFile,
  XmaxStorageProgressListener,
  XmaxUploadedFile
} from './XmaxStorageModel';

/** An interface for uploading and downloading media files. */
export interface XmaxStorageManaging {

  /**
   * Uploads encoded image data.
   *
   * @param data The image data.
   * @param fileName The filename.
   * @param contentType The content MIME type.
   * @param progress The transfer progress handler.
   *
   * @returns The uploaded file information.
   */
  uploadImage(
    data: ArrayBuffer,
    fileName: string,
    contentType: string,
    progress?: XmaxStorageProgressListener
  ): Promise<XmaxUploadedFile>;

  /**
   * Uploads a local image file.
   *
   * @param filePath The local file path.
   * @param contentType The content MIME type.
   * @param progress The transfer progress handler.
   *
   * @returns The uploaded file information.
   */
  uploadImageFile(
    filePath: string,
    contentType?: string,
    progress?: XmaxStorageProgressListener
  ): Promise<XmaxUploadedFile>;

  /**
   * Uploads encoded image data and checks its content.
   *
   * @param data The image data.
   * @param fileName The filename.
   * @param contentType The content MIME type.
   * @param progress The transfer progress handler.
   *
   * @returns The uploaded file information.
   */
  uploadImageWithSafetyCheck(
    data: ArrayBuffer,
    fileName: string,
    contentType: string,
    progress?: XmaxStorageProgressListener
  ): Promise<XmaxUploadedFile>;

  /**
   * Uploads a local image file and checks its content.
   *
   * @param filePath The local file path.
   * @param contentType The content MIME type.
   * @param progress The transfer progress handler.
   *
   * @returns The uploaded file information.
   */
  uploadImageFileWithSafetyCheck(
    filePath: string,
    contentType?: string,
    progress?: XmaxStorageProgressListener
  ): Promise<XmaxUploadedFile>;

  /**
   * Uploads encoded video data.
   *
   * @param data The video data.
   * @param fileName The filename.
   * @param contentType The content MIME type.
   * @param progress The transfer progress handler.
   *
   * @returns The uploaded file information.
   */
  uploadVideo(
    data: ArrayBuffer,
    fileName: string,
    contentType: string,
    progress?: XmaxStorageProgressListener
  ): Promise<XmaxUploadedFile>;

  /**
   * Uploads a local video file.
   *
   * @param filePath The local file path.
   * @param contentType The content MIME type.
   * @param progress The transfer progress handler.
   *
   * @returns The uploaded file information.
   */
  uploadVideoFile(
    filePath: string,
    contentType?: string,
    progress?: XmaxStorageProgressListener
  ): Promise<XmaxUploadedFile>;

  /**
   * Downloads an image to a local file.
   *
   * @param remoteUrl The remote file URL.
   * @param destinationPath The destination file path.
   * @param progress The transfer progress handler.
   *
   * @returns The downloaded file information.
   */
  downloadImage(
    remoteUrl: string,
    destinationPath: string,
    progress?: XmaxStorageProgressListener
  ): Promise<XmaxDownloadedFile>;

  /**
   * Downloads a video to a local file.
   *
   * @param remoteUrl The remote file URL.
   * @param destinationPath The destination file path.
   * @param progress The transfer progress handler.
   *
   * @returns The downloaded file information.
   */
  downloadVideo(
    remoteUrl: string,
    destinationPath: string,
    progress?: XmaxStorageProgressListener
  ): Promise<XmaxDownloadedFile>;
}
