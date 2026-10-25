//
//  ImageController.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { image } from '@kit.ImageKit';
import {
  XmaxError,
  XmaxErrorCode
} from '../../foundation/errors/XmaxError';
import { ImageManager } from '../../foundation/media/image/ImageManager';
import { ImageManaging } from '../../foundation/media/image/ImageManaging';
import { VideoFrame } from '../../foundation/media/video/VideoFrame';
import { RtcManaging } from '../../foundation/rtc/RtcManaging';
import { VideoContentMode } from '../../foundation/media/video/VideoContentMode';
import { ImageSourceController } from '../../media/image/ImageSourceController';
import { ImageSourceControlling } from '../../media/image/ImageSourceControlling';
import {
  VideoRenderBinding,
  VideoRenderRegistry
} from '../../rendering/video/VideoRenderRegistry';
import { MediaService } from '../../service/media/MediaService';
import { MediaServicing } from '../../service/media/MediaServicing';
import { RealtimeMediaStream } from '../../service/realtime/RealtimeMediaStream';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import { RealtimeVideoTrack } from '../../service/realtime/RealtimeVideoTrack';
import { StreamControlling } from '../../stream/StreamControlling';
import { StreamId } from '../../stream/StreamId';

/** Coordinates local image decoding, repeated frames, encoding, and preview resources. */
export class ImageController {

  /** The adapter for RTC engine, room, and media services. */
  private readonly rtcManager: RtcManaging;

  /** The manager decoding platform images into SDK-owned resources. */
  private readonly imageManager: ImageManaging;

  /** The service resolving model-specific media dimensions. */
  private readonly mediaService: MediaServicing;

  /** The source preparing and repeating local image frames. */
  private readonly imageSourceController: ImageSourceControlling;

  /** The controller coordinating RTC rooms, streams, and signaling. */
  private readonly streamController: StreamControlling;

  /** The local track owned by the current media source. */
  private activeTrack: RealtimeVideoTrack | null = null;

  /** Whether the current source may deliver media frames. */
  private acceptsFrames: boolean = false;

  /**
   * Creates an image media controller.
   *
   * @param rtcManager The RTC services for external video and local rendering.
   * @param streamController The controller for encoding configuration and video transport.
   * @param errorListener The continuous image frame error handler.
   * @param mediaService The model's media sizing service.
   */
  constructor(
    rtcManager: RtcManaging,
    streamController: StreamControlling,
    errorListener: (
      error: XmaxError
    ) => void,
    mediaService: MediaServicing = new MediaService()
  ) {
    // Foundation components
    this.rtcManager = rtcManager;
    this.imageManager = new ImageManager();

    // Service components
    this.mediaService = mediaService;

    // Business components
    this.streamController = streamController;
    this.imageSourceController = new ImageSourceController(
      this.imageManager,
      this.mediaService,
      (frame: VideoFrame): void => {
        if (!this.acceptsFrames) {
          return;
        }

        this.streamController.pushLocalVideoFrame(frame);
      },
      (error: XmaxError): void => {
        if (!this.acceptsFrames) {
          return;
        }

        errorListener(error);
      }
    );
  }

  /** The current local input track, or null without local media. */
  get currentTrack(): RealtimeVideoTrack | null {
    return this.activeTrack;
  }

  /**
   * Creates a continuous frame stream from image input.
   *
   * @param source A local file path, encoded image bytes, or platform PixelMap.
   * @param videoFormat The optional output format, resolved from image metadata if omitted.
   *
   * @returns The created local image stream.
   */
  async createLocalImageStream(
    source: string | ArrayBuffer | Uint8Array | image.PixelMap,
    videoFormat?: RealtimeVideoFormat
  ): Promise<RealtimeMediaStream> {
    if (this.activeTrack !== null) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Stop the current local image stream before creating another one'
      );
    }

    return this.createStream(
      source,
      videoFormat
    );
  }

  /**
   * Stops image output and releases preview bindings.
   *
   * The Promise fulfills after stopping.
   */
  async stopLocalImageStream(): Promise<void> {
    this.prepareForStop();
    this.activeTrack = null;
  }

  /** Stops image output and detaches preview immediately. */
  prepareForStop(): void {
    this.acceptsFrames = false;
    this.imageSourceController.stop();

    const track: RealtimeVideoTrack | null = this.activeTrack;
    if (track !== null) {
      VideoRenderRegistry.unregister(track);
      this.rtcManager.unbindLocalVideo();
    }
  }

  /**
   * Prepares image output, encoding, transport, and preview resources.
   *
   * @param source A local file path, encoded image bytes, or platform PixelMap.
   * @param videoFormat The optional video output format.
   *
   * @returns The image stream after resource setup.
   */
  private async createStream(
    source: string | ArrayBuffer | Uint8Array | image.PixelMap,
    videoFormat?: RealtimeVideoFormat
  ): Promise<RealtimeMediaStream> {
    let track: RealtimeVideoTrack | null = null;

    try {
      const resolvedFormat: RealtimeVideoFormat =
        await this.imageSourceController.prepare(
          source,
          videoFormat
        );
      track = new RealtimeVideoTrack(
        'video0',
        resolvedFormat
      );

      this.streamController.setVideoEncoderConfig(resolvedFormat);
      this.rtcManager.useExternalVideoSource();

      this.registerPreview(track);
      this.acceptsFrames = true;
      this.imageSourceController.start();

      this.activeTrack = track;

      return new RealtimeMediaStream(
        StreamId.LOCAL,
        track
      );
    } catch (error) {
      this.acceptsFrames = false;
      this.imageSourceController.stop();

      if (track !== null) {
        VideoRenderRegistry.unregister(track);
      }

      throw XmaxError.from(error);
    }
  }

  /**
   * Registers RTC preview for a local image track.
   *
   * @param track The local image track to display.
   */
  private registerPreview(
    track: RealtimeVideoTrack
  ): void {
    VideoRenderRegistry.register(
      track,
      new VideoRenderBinding(
        this.rtcManager.renderLibraryName(),
        (
          viewId: string,
          contentMode: VideoContentMode
        ): void => {
          this.rtcManager.bindLocalVideo(
            viewId,
            contentMode
          );
        },
        (_viewId: string): void => {
          this.rtcManager.unbindLocalVideo();
        }
      )
    );
  }

}
