//
//  ExternalVideoController.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { XmaxError, XmaxErrorCode } from '../../foundation/errors/XmaxError';
import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import { RtcManaging } from '../../foundation/rtc/RtcManaging';
import { VideoContentMode } from '../../foundation/media/video/VideoContentMode';
import { VideoRenderBinding, VideoRenderRegistry } from '../../rendering/video/VideoRenderRegistry';
import { MediaServicing } from '../../service/media/MediaServicing';
import { ImageSize } from '../../service/media/ImageSize';
import { RealtimeMediaSource } from '../../service/media/RealtimeMediaSource';
import { RealtimeMediaStream } from '../../service/realtime/RealtimeMediaStream';
import { RealtimeVideoTrack } from '../../service/realtime/RealtimeVideoTrack';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import { StreamControlling } from '../../stream/StreamControlling';
import { StreamId } from '../../stream/StreamId';
import { ExternalVideoFrameSink } from './ExternalVideoFrameSink';
import { RealtimeExternalVideoSource } from './RealtimeExternalVideoSource';

/** Binds an app-owned external video source to local preview and RTC. */
export class ExternalVideoController {

  /** RTC source configuration and local preview binding. */
  private readonly rtcManager: RtcManaging;

  /** Shared encoding and SEI-aware audio/video transport. */
  private readonly streamController: StreamControlling;

  /** Model-specific media sizing. */
  private readonly mediaService: MediaServicing;

  /** Continuous media failure handler. */
  private readonly errorListener: (
    error: XmaxError
  ) => void;

  /** The bound app-owned source, cleared before awaiting stop. */
  private source: RealtimeExternalVideoSource | null = null;

  /** The synchronous receiver scoped to this binding. */
  private sink: ExternalVideoFrameSink | null = null;

  /** The SDK preview track, absent after unbinding. */
  private track: RealtimeVideoTrack | null = null;

  /** Whether this binding owns an external audio source. */
  private audioEnabled: boolean = false;

  /** Cancels a pending source.start without waiting for an uncooperative producer Promise. */
  private cancelStart: (() => void) | null = null;

  /** Creates an external source lifecycle and preview controller. */
  constructor(
    rtcManager: RtcManaging,
    streamController: StreamControlling,
    mediaService: MediaServicing,
    errorListener: (
      error: XmaxError
    ) => void
  ) {
    this.rtcManager = rtcManager;
    this.streamController = streamController;
    this.mediaService = mediaService;
    this.errorListener = errorListener;
  }

  /** The current external preview track. */
  get currentTrack(): RealtimeVideoTrack | null {
    return this.track;
  }

  /** Whether the active source supplies external audio. */
  get hasAudio(): boolean {
    return this.audioEnabled;
  }

  /**
   * Binds the source without taking ownership of its devices or requiring camera permissions.
   *
   * @param source The app-owned producer with fixed source format and optional audio.
   * @returns A local stream for preview, connection, and generation.
   */
  async createExternalVideoStream(
    source: RealtimeExternalVideoSource
  ): Promise<RealtimeMediaStream> {
    if (this.source !== null) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Stop the current external video stream before creating another one'
      );
    }

    const requested: RealtimeVideoFormat = source.videoFormat;
    const hasAudio: boolean = source.hasAudio ?? false;
    requested.validate();
    if (requested.width > 32768 || requested.height > 32768 || requested.width * requested.height > 16777216) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'External video input exceeds supported buffer dimensions'
      );
    }
    const size: ImageSize = this.mediaService.resolveMediaSize(
      new ImageSize(
        requested.width,
        requested.height
      ),
      RealtimeMediaSource.EXTERNAL
    );
    const format: RealtimeVideoFormat = requested.resized(
      size.width,
      size.height
    );
    format.validate();
    const track = new RealtimeVideoTrack(
      'external0',
      format
    );
    const sink = new ExternalVideoFrameSink(
      requested.resized(
        requested.width,
        requested.height
      ),
      format,
      hasAudio,
      (frame): void => this.streamController.pushLocalVideoFrame(frame),
      (frame): void => this.streamController.pushLocalAudioFrame(frame),
      this.errorListener
    );
    this.source = source;
    this.sink = sink;
    this.track = track;

    try {
      this.streamController.setVideoEncoderConfig(format);
      this.rtcManager.useExternalVideoSource();
      if (hasAudio) {
        this.rtcManager.startExternalAudioSource();
        this.audioEnabled = true;
      }

      VideoRenderRegistry.register(
        track,
        new VideoRenderBinding(
          this.rtcManager.renderLibraryName(),
          (viewId: string, contentMode: VideoContentMode): void => this.rtcManager.bindLocalVideo(
            viewId,
            contentMode
          ),
          (_viewId: string): void => this.rtcManager.unbindLocalVideo()
        )
      );
      const cancelled: Promise<void> = new Promise<void>((_resolve, reject): void => {
        this.cancelStart = (): void => reject(new XmaxError(
          XmaxErrorCode.CANCELLED,
          'External source binding was cancelled'
        ));
      });
      const starting: Promise<void> = Promise.resolve().then((): Promise<void> => {
        if (!sink.isRequestingFrames) {
          throw new XmaxError(
            XmaxErrorCode.CANCELLED,
            'External source binding was cancelled'
          );
        }
        return source.start(sink);
      });
      await Promise.race([starting, cancelled]);
      if (!sink.isRequestingFrames) {
        throw new XmaxError(
          XmaxErrorCode.MEDIA_ERROR,
          'External video source failed during setup'
        );
      }

      return new RealtimeMediaStream(
        StreamId.LOCAL,
        track
      );
    } catch (error) {
      try {
        await this.stopExternalVideoStream();
      } catch (cleanupError) {
        XmaxLogger.error(
          'Failed to stop external source during rollback: ' +
          XmaxError.from(cleanupError).message,
          'Media'
        );
      }
      throw XmaxError.from(error);
    } finally {
      this.cancelStart = null;
    }
  }

  /** Immediately invalidates old callbacks and detaches SDK preview before asynchronous cleanup. */
  prepareForStop(): void {
    this.sink?.invalidate();
    this.cancelStart?.();
    this.cancelStart = null;
    if (this.track !== null) {
      VideoRenderRegistry.unregister(this.track);
      try {
        this.rtcManager.unbindLocalVideo();
      } catch (error) {
        XmaxLogger.error(
          'Failed to detach external video preview: ' + XmaxError.from(error).message,
          'Media'
        );
      }
    }
  }

  /** Unbinds the source and calls stop once, leaving app-owned capture resources to the app. */
  async stopExternalVideoStream(): Promise<void> {
    this.prepareForStop();
    const source: RealtimeExternalVideoSource | null = this.source;
    const hadAudio: boolean = this.audioEnabled;
    this.source = null;
    this.sink = null;
    this.track = null;
    this.audioEnabled = false;

    try {
      if (hadAudio) {
        this.rtcManager.stopExternalAudioSource();
      }
    } finally {
      await source?.stop();
    }
  }
}
