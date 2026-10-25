//
//  ImageSourceController.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { RealtimeMediaSource } from '../../service/realtime/RealtimeMediaSource';
import { image } from '@kit.ImageKit';
import {
  XmaxError,
  XmaxErrorCode
} from '../../foundation/errors/XmaxError';
import { DecodedImage } from '../../foundation/media/image/DecodedImage';
import { ImageManaging } from '../../foundation/media/image/ImageManaging';
import { ImageVideoFrameData } from '../../foundation/media/image/ImageVideoFrameData';
import { BufferVideoFrame } from '../../foundation/media/video/BufferVideoFrame';
import { VideoFormat } from '../../foundation/media/video/VideoFormat';
import { VideoFramePlane } from '../../foundation/media/video/VideoFramePlane';
import { ImageSize } from '../../service/media/ImageSize';
import { MediaServicing } from '../../service/media/MediaServicing';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import { MediaTimeline } from '../MediaTimeline';
import {
  ImageSourceControlling,
  ImageSourceErrorListener,
  ImageSourceFrameListener
} from './ImageSourceControlling';

/** Processes an image into continuous target-sized video frames at a fixed rate. */
export class ImageSourceController implements ImageSourceControlling {

  /** The manager decoding platform images into SDK-owned resources. */
  private readonly imageManager: ImageManaging;

  /** The service resolving model-specific media dimensions. */
  private readonly mediaService: MediaServicing;

  /** The receiver for prepared media frames. */
  private readonly frameListener: ImageSourceFrameListener;

  /** The handler for asynchronous component failures. */
  private readonly errorListener: ImageSourceErrorListener;

  /** The prepared image frame dimensions and pixel layout. */
  private frameFormat: VideoFormat | null = null;

  /** The reusable image pixel plane for repeated output. */
  private framePlane: VideoFramePlane | null = null;

  /** The current video dimensions, frame rate, and encoding settings. */
  private videoFormat: RealtimeVideoFormat | null = null;

  /** The timer pacing repeated image frame output. */
  private frameTimer: number = -1;

  /** Creates an image source controller. */
  constructor(
    imageManager: ImageManaging,
    mediaService: MediaServicing,
    frameListener: ImageSourceFrameListener,
    errorListener: ImageSourceErrorListener
  ) {
    // Foundation components
    this.imageManager = imageManager;

    // Service components
    this.mediaService = mediaService;

    // Image frame listener
    this.frameListener = frameListener;
    this.errorListener = errorListener;
  }

  /**
   * Loads an image and prepares reusable frame pixels.
   *
   * @param source A local file path, encoded image bytes, or platform PixelMap.
   * @param videoFormat The requested format, resolved from image dimensions if omitted.
   *
   * @returns The resolved image output format.
   */
  async prepare(
    source: string | ArrayBuffer | Uint8Array | image.PixelMap,
    videoFormat?: RealtimeVideoFormat
  ): Promise<RealtimeVideoFormat> {
    if (this.framePlane !== null) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Stop the current image source before preparing another image'
      );
    }

    let decodedImage: DecodedImage | null = null;

    try {
      decodedImage = await this.decode(source);
      const resolvedFormat: RealtimeVideoFormat = this.resolveVideoFormat(
        new ImageSize(
          decodedImage.width,
          decodedImage.height
        ),
        videoFormat
      );

      const frameData: ImageVideoFrameData =
        await decodedImage.makeVideoFrameData(
          resolvedFormat.width,
          resolvedFormat.height
        );

      this.frameFormat = new VideoFormat(
        frameData.width,
        frameData.height,
        frameData.pixelFormat
      );
      this.framePlane = new VideoFramePlane(
        frameData.data,
        frameData.bytesPerRow
      );
      this.videoFormat = resolvedFormat;

      return resolvedFormat;
    } catch (error) {
      throw XmaxError.from(error);
    } finally {
      if (decodedImage !== null) {
        await decodedImage.release();
      }
    }
  }

  /**
   * Normalizes public image input into an SDK-owned decoded image.
   *
   * @param source A local file path, encoded image bytes, or platform PixelMap.
   *
   * @returns The decoded image owned by XmaxSDK.
   */
  private decode(
    source: string | ArrayBuffer | Uint8Array | image.PixelMap
  ): Promise<DecodedImage> {
    if (typeof source === 'string') {
      return this.imageManager.decodeFile(source);
    }
    if (source instanceof ArrayBuffer || source instanceof Uint8Array) {
      return this.imageManager.decode(source);
    }
    return this.imageManager.decodePixelMap(source);
  }

  /** Outputs prepared image frames at the target rate. */
  start(): void {
    const videoFormat: RealtimeVideoFormat | null = this.videoFormat;
    if (videoFormat === null || this.frameFormat === null ||
      this.framePlane === null) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Prepare the local image before starting the image source'
      );
    }
    if (this.frameTimer >= 0) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Local image source is already active'
      );
    }

    this.emitFrame();
    this.frameTimer = setInterval(
      (): void => {
        try {
          this.emitFrame();
        } catch (error) {
          this.errorListener(XmaxError.from(error));
        }
      },
      1000 / videoFormat.fps
    );
  }

  /** Stops image output and clears prepared pixels. */
  stop(): void {
    if (this.frameTimer >= 0) {
      clearInterval(this.frameTimer);
      this.frameTimer = -1;
    }

    this.frameFormat = null;
    this.framePlane = null;
    this.videoFormat = null;
  }

  /** Outputs an image frame with the current timestamp. */
  private emitFrame(): void {
    const frameFormat: VideoFormat | null = this.frameFormat;
    const framePlane: VideoFramePlane | null = this.framePlane;
    if (frameFormat === null || framePlane === null) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Local image frame is unavailable'
      );
    }

    this.frameListener(new BufferVideoFrame(
      frameFormat,
      MediaTimeline.currentTimestampUs(),
      [framePlane]
    ));
  }

  /**
   * Resolves the model input format from image dimensions and the requested format.
   *
   * @param sourceSize The source image dimensions.
   * @param videoFormat The requested video output format.
   *
   * @returns The validated and adapted video format.
   */
  private resolveVideoFormat(
    sourceSize: ImageSize,
    videoFormat?: RealtimeVideoFormat
  ): RealtimeVideoFormat {
    const requestedFormat: RealtimeVideoFormat = videoFormat ??
      new RealtimeVideoFormat(
        sourceSize.width,
        sourceSize.height,
        this.mediaService.model.defaultFrameRate
      );
    if (!Number.isFinite(requestedFormat.fps) || requestedFormat.fps <= 0) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Image stream frame rate must be a finite number greater than zero'
      );
    }

    const targetSize: ImageSize = this.mediaService.resolveMediaSize(
      new ImageSize(
        requestedFormat.width,
        requestedFormat.height
      ),
      RealtimeMediaSource.IMAGE
    );

    const resolvedFormat: RealtimeVideoFormat = requestedFormat.resized(
      targetSize.width,
      targetSize.height
    );
    resolvedFormat.validate();

    return resolvedFormat;
  }

}
