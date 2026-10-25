//
//  MediaSourceController.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { RealtimeMediaSource } from '../service/media/RealtimeMediaSource';
import { fileIo } from '@kit.CoreFileKit';
import { media } from '@kit.MediaKit';
import { AudioFrame } from '../foundation/media/audio/AudioFrame';
import { AudioManaging } from '../foundation/media/audio/AudioManaging';
import {
  XmaxError,
  XmaxErrorCode
} from '../foundation/errors/XmaxError';
import { XmaxLogger } from '../foundation/logging/XmaxLogger';
import { VideoRotation } from '../foundation/media/video/VideoRotation';
import { ImageSize } from '../service/media/ImageSize';
import { MediaServicing } from '../service/media/MediaServicing';
import { RealtimeVideoFormat } from '../service/realtime/RealtimeVideoFormat';
import { AudioSourceController } from './audio/AudioSourceController';
import { AudioSourceControlling } from './audio/AudioSourceControlling';
import {
  VideoSourceControlling,
  VideoSourceErrorListener,
  VideoSourceFrameListener
} from './video/VideoSourceControlling';
import { VideoSourceController } from './video/VideoSourceController';
import { MediaSourceConfiguration } from './MediaSourceConfiguration';
import { MediaSourceControlling } from './MediaSourceControlling';
import { MediaTimeline } from './MediaTimeline';

/**
 * Receives PCM frames on the playback timeline.
 *
 * @param frame The decoded 48 kHz mono PCM frame on the shared file playback timeline.
 */
export type MediaSourceAudioFrameListener = (
  frame: AudioFrame
) => void;

/** Audio/video metadata for a local media file. */
class MediaSourceMetadata {

  // Source video format and rotation

  /** The source video width, in pixels. */
  readonly width: number;

  /** The source video height, in pixels. */
  readonly height: number;

  /** The clockwise video rotation. */
  readonly rotation: VideoRotation;

  // File duration and audio track information

  /** The media file duration, in microseconds. */
  readonly durationUs: number;

  /** Whether the media source includes an available audio track. */
  readonly hasAudio: boolean;

  /** Creates media file metadata. */
  constructor(
    width: number,
    height: number,
    rotation: VideoRotation,
    durationUs: number,
    hasAudio: boolean
  ) {
    this.width = width;
    this.height = height;
    this.rotation = rotation;
    this.durationUs = durationUs;
    this.hasAudio = hasAudio;
  }
}

/** Coordinates local media file decoding, synchronization, and looping. */
export class MediaSourceController implements MediaSourceControlling {

  // Audio/video source and sizing dependencies

  /** The player for SDK-managed local PCM preview. */
  private readonly audioManager: AudioManaging;

  // Service components

  /** The service resolving model-specific media dimensions. */
  private readonly mediaService: MediaServicing;

  // Media components

  /** The source decoding file video on the shared timeline. */
  private readonly videoSourceController: VideoSourceControlling;

  /** The source decoding file audio on the shared timeline. */
  private readonly audioSourceController: AudioSourceControlling;

  // File metadata and playback timeline

  /** The prepared source file metadata. */
  private metadata: MediaSourceMetadata | null = null;

  /** The playback timeline shared by audio and video. */
  private timeline: MediaTimeline | null = null;

  // Playback and completion coordination

  /** Whether media output is paused. */
  private isPaused: boolean = false;

  /** Whether video output has reached the file end. */
  private videoEnded: boolean = false;

  /** Whether audio output has reached the file end. */
  private audioEnded: boolean = false;

  /** Whether track completion is awaiting local audio draining. */
  private completionPending: boolean = false;

  /** Whether playback completion has already been delivered. */
  private completionNotified: boolean = false;

  // Asynchronous playback revision

  /** The revision rejecting events from obsolete playback runs. */
  private playbackVersion: number = 0;

  /** Reports local media playback completion. */
  private readonly endedListener: () => void;

  /** The handler for asynchronous component failures. */
  private readonly errorListener: VideoSourceErrorListener;

  /**
   * Creates a media source controller.
   *
   * @param mediaService The service resolving model input dimensions.
   * @param audioManager The audio manager for external audio playback and delivery.
   * @param videoFrameListener The video frame handler.
   * @param audioFrameListener The audio frame handler.
   * @param errorListener The media source error handler.
   * @param endedListener The current playback completion handler.
   */
  constructor(
    mediaService: MediaServicing,
    audioManager: AudioManaging,
    videoFrameListener: VideoSourceFrameListener,
    audioFrameListener: MediaSourceAudioFrameListener,
    errorListener: VideoSourceErrorListener,
    endedListener: () => void = (): void => { }
  ) {
    // Foundation components
    this.audioManager = audioManager;

    // Service components
    this.mediaService = mediaService;
    this.endedListener = endedListener;
    this.errorListener = errorListener;

    // Media components
    this.videoSourceController = new VideoSourceController(
      videoFrameListener,
      errorListener,
      (): void => {
        this.videoEnded = true;
        void this.finishPlaybackIfEnded();
      }
    );

    this.audioSourceController = new AudioSourceController(
      (frame: AudioFrame): void => {
        this.audioManager.write(frame);
        audioFrameListener(frame);
      },
      errorListener,
      (): void => {
        this.audioEnded = true;
        void this.finishPlaybackIfEnded();
      }
    );
  }

  /** Whether the current file source has an available audio track. */
  get hasAudio(): boolean {
    return this.metadata?.hasAudio ?? false;
  }

  /** Whether all available file audio and video tracks have ended. */
  get hasEnded(): boolean {
    return this.completionNotified;
  }

  /**
   * Reads local media metadata and configures audio/video sources.
   *
   * @param filePath The local media file path.
   * @param videoFormat The requested format, resolved from file metadata if omitted.
   * @param loop Whether to loop after file completion.
   *
   * @returns The resolved media source configuration.
   */
  async prepare(
    filePath: string,
    videoFormat?: RealtimeVideoFormat,
    loop: boolean = true
  ): Promise<MediaSourceConfiguration> {
    if (this.metadata !== null) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Stop the current local video before preparing another one'
      );
    }
    if (filePath.trim().length === 0) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Local video file path must not be empty'
      );
    }

    const metadata: MediaSourceMetadata = await this.readMetadata(filePath);
    const resolvedFormat: RealtimeVideoFormat = this.resolveVideoFormat(
      metadata,
      videoFormat
    );

    this.videoSourceController.configure(
      filePath,
      metadata.rotation,
      resolvedFormat.width,
      resolvedFormat.height,
      resolvedFormat.fps,
      loop
    );
    if (metadata.hasAudio) {
      this.audioSourceController.configure(
        filePath,
        loop
      );
    }

    this.metadata = metadata;
    return new MediaSourceConfiguration(
      resolvedFormat,
      metadata.hasAudio
    );
  }

  /**
   * Starts synchronized audio/video output at the file origin.
   *
   * The Promise fulfills after media source startup.
   */
  async start(): Promise<void> {
    const metadata: MediaSourceMetadata = this.requireMetadata();

    this.playbackVersion++;
    const version: number = this.playbackVersion;
    this.videoEnded = false;
    this.audioEnded = !metadata.hasAudio;
    this.completionPending = false;
    this.completionNotified = false;

    if (metadata.hasAudio) {
      await this.audioManager.start();
    }
    if (version !== this.playbackVersion) {
      throw new XmaxError(
        XmaxErrorCode.CANCELLED,
        'Media initialization was cancelled'
      );
    }

    const timeline = new MediaTimeline(
      0,
      metadata.durationUs
    );
    this.timeline = timeline;
    this.isPaused = false;

    try {
      await this.videoSourceController.start(timeline);
      if (version !== this.playbackVersion) {
        throw new XmaxError(
          XmaxErrorCode.CANCELLED,
          'Media initialization was cancelled'
        );
      }

      if (metadata.hasAudio) {
        this.audioSourceController.start(timeline);
      }
    } catch (error) {
      if (version !== this.playbackVersion) {
        throw XmaxError.from(error);
      }

      this.playbackVersion++;
      const videoStopPromise: Promise<void> = this.videoSourceController.stop();
      this.audioSourceController.stop();
      await videoStopPromise;
      await this.audioManager.stop();

      this.timeline = null;
      throw XmaxError.from(error);
    }
  }

  /** Pauses the file timeline and clears buffered local audio. */
  async pause(): Promise<void> {
    if (this.isPaused) {
      return;
    }

    const timeline: MediaTimeline | null = this.timeline;
    if (timeline === null) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Local media source is not active'
      );
    }

    timeline.pause();
    this.isPaused = true;

    try {
      this.videoSourceController.pause();
      if (this.hasAudio) {
        this.audioSourceController.pause();
        await this.audioManager.flush();
      }
    } catch (error) {
      const pausedDurationUs: number = timeline.resume();
      try {
        this.videoSourceController.resume(pausedDurationUs);
        if (this.hasAudio) {
          this.audioSourceController.resume(pausedDurationUs);
        }
      } catch (resumeError) {
        XmaxLogger.error(
          `${XmaxLogger.localized("回滚本地视频暂停失败 (Failed to Roll Back Local Video Pause)\n└─ 原因：", "回滚本地视频暂停失败 (Failed to Roll Back Local Video Pause)\n└─ Reason: ")}${XmaxError.from(resumeError).message}`,
          'Video'
        );
      }

      this.isPaused = false;
      throw XmaxError.from(error);
    }
  }

  /** Resumes the file timeline at its paused media position. */
  resume(): void {
    if (!this.isPaused) {
      return;
    }

    const timeline: MediaTimeline | null = this.timeline;
    if (timeline === null) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Local media source is not active'
      );
    }

    const pausedDurationUs: number = timeline.resume();
    this.videoSourceController.resume(pausedDurationUs);
    if (this.hasAudio) {
      this.audioSourceController.resume(pausedDurationUs);
    }

    this.isPaused = false;
    void this.finishPlaybackIfEnded();
  }

  /** Notifies playback completion after both tracks end and local audio drains. */
  private async finishPlaybackIfEnded(): Promise<void> {
    if (!this.videoEnded || !this.audioEnded || this.isPaused || this.timeline === null ||
      this.completionPending || this.completionNotified) {
      return;
    }

    const version: number = this.playbackVersion;
    this.completionPending = true;
    try {
      if (this.hasAudio) {
        await this.audioManager.drain();
      }
      if (version !== this.playbackVersion || this.isPaused || this.timeline === null) {
        return;
      }

      this.completionNotified = true;
      this.endedListener();
    } catch (error) {
      if (version === this.playbackVersion) {
        this.errorListener(XmaxError.from(error).message);
      }
    } finally {
      if (version === this.playbackVersion) {
        this.completionPending = false;
      }
    }
  }

  /**
   * Enables local audio preview without affecting RTC audio output.
   *
   * @param enabled Whether to play local preview audio.
   */
  setLocalAudioPreviewEnabled(
    enabled: boolean
  ): void {
    this.audioManager.setPlaybackEnabled(enabled);
  }

  /** The configured local file preview volume in 0 to 1; zero mutes and one uses original volume. */
  get localAudioVolume(): number {
    return this.audioManager.volume;
  }

  /**
   * Sets preview volume without changing audio frames for other consumers.
   *
   * @param volume The volume in 0 to 1, from muted to original volume.
   */
  async setLocalAudioVolume(
    volume: number
  ): Promise<void> {
    await this.audioManager.setVolume(volume);
  }

  /**
   * Stops audio/video output and clears media file state.
   *
   * The Promise fulfills after media source stopping.
   */
  async stop(): Promise<void> {
    this.playbackVersion++;
    this.videoEnded = false;
    this.audioEnded = false;
    this.completionPending = false;
    this.completionNotified = false;

    const videoStopPromise: Promise<void> = this.videoSourceController.stop();
    this.audioSourceController.stop();
    await videoStopPromise;
    await this.stopAudioPlayback();

    this.metadata = null;
    this.timeline = null;
    this.isPaused = false;
  }

  /**
   * Returns prepared media file metadata.
   *
   * @returns The current file metadata.
   */
  private requireMetadata(): MediaSourceMetadata {
    const metadata: MediaSourceMetadata | null = this.metadata;
    if (metadata === null) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Prepare the local media file before starting the media source'
      );
    }

    return metadata;
  }

  /**
   * Stops local audio playback and logs stopping errors.
   *
   * The Promise fulfills after the stop attempt.
   */
  private async stopAudioPlayback(): Promise<void> {
    try {
      await this.audioManager.stop();
    } catch (error) {
      const reason: string = error instanceof Error ? error.message : String(error);
      XmaxLogger.error(
        `${XmaxLogger.localized("释放本地音频播放器失败 (Failed to Release Local Audio Player)\n└─ 原因：", "释放本地音频播放器失败 (Failed to Release Local Audio Player)\n└─ Reason: ")}${reason}`,
        'Audio'
      );
    }
  }

  /**
   * Reads video dimensions, rotation, duration, and audio availability from a local file.
   *
   * @param filePath The local media file path.
   *
   * @returns The parsed media file metadata.
   */
  private async readMetadata(
    filePath: string
  ): Promise<MediaSourceMetadata> {
    const sourceFile: fileIo.File = fileIo.openSync(
      filePath,
      fileIo.OpenMode.READ_ONLY
    );
    let extractor: media.AVMetadataExtractor | null = null;

    try {
      extractor = await media.createAVMetadataExtractor();
      extractor.fdSrc = {
        fd: sourceFile.fd,
        offset: 0,
        length: fileIo.statSync(sourceFile.fd).size
      };

      const metadata: media.AVMetadata = await extractor.fetchMetadata();
      const width: number = Number.parseInt(metadata.videoWidth ?? '');
      const height: number = Number.parseInt(metadata.videoHeight ?? '');
      const durationMs: number = Number.parseFloat(metadata.duration ?? '');
      if (!Number.isFinite(width) || !Number.isFinite(height) ||
        !Number.isFinite(durationMs) || width <= 0 || height <= 0 ||
        durationMs <= 0) {
        throw new XmaxError(
          XmaxErrorCode.INVALID_CONFIGURATION,
          'The selected file does not contain a valid video track'
        );
      }

      return new MediaSourceMetadata(
        width,
        height,
        this.resolveRotation(metadata.videoOrientation),
        durationMs * 1000,
        this.resolveHasAudio(metadata.hasAudio)
      );
    } finally {
      try {
        if (extractor !== null) {
          await extractor.release();
        }
      } catch (error) {
        const reason: string = error instanceof Error ? error.message : String(error);
        XmaxLogger.error(
          `${XmaxLogger.localized("释放视频元数据读取器失败 (Failed to Release Video Metadata Reader)\n└─ 原因：", "释放视频元数据读取器失败 (Failed to Release Video Metadata Reader)\n└─ Reason: ")}${reason}`,
          'Video'
        );
      } finally {
        fileIo.closeSync(sourceFile);
      }
    }
  }

  /**
   * Resolves model input format from file display size and the requested format.
   *
   * @param metadata The media file metadata.
   * @param videoFormat The requested video output format.
   *
   * @returns The resolved model input format.
   */
  private resolveVideoFormat(
    metadata: MediaSourceMetadata,
    videoFormat?: RealtimeVideoFormat
  ): RealtimeVideoFormat {
    const displaySize: ImageSize = this.displaySize(metadata);
    const requestedFormat: RealtimeVideoFormat = videoFormat ?? new RealtimeVideoFormat(
      displaySize.width,
      displaySize.height,
      this.mediaService.model.defaultFrameRate
    );

    const targetSize: ImageSize = this.mediaService.resolveMediaSize(
      new ImageSize(
        requestedFormat.width,
        requestedFormat.height
      ),
      RealtimeMediaSource.VIDEO
    );

    const resolvedFormat: RealtimeVideoFormat = requestedFormat.resized(
      targetSize.width,
      targetSize.height
    );
    resolvedFormat.validate();
    return resolvedFormat;
  }

  /**
   * Resolves file display dimensions after rotation.
   *
   * @param metadata The media file metadata.
   *
   * @returns The oriented display dimensions.
   */
  private displaySize(
    metadata: MediaSourceMetadata
  ): ImageSize {
    if (metadata.rotation === VideoRotation.ROTATION_90 ||
      metadata.rotation === VideoRotation.ROTATION_270) {
      return new ImageSize(
        metadata.height,
        metadata.width
      );
    }

    return new ImageSize(
      metadata.width,
      metadata.height
    );
  }

  /**
   * Normalizes metadata rotation into a video rotation.
   *
   * @param value The rotation angle from media metadata.
   *
   * @returns The normalized video rotation.
   */
  private resolveRotation(
    value?: string
  ): VideoRotation {
    const rawRotation: number = Number.parseInt(value ?? '0');
    const normalizedRotation: number = Number.isFinite(rawRotation) ?
      ((rawRotation % 360) + 360) % 360 : 0;

    switch (normalizedRotation) {
      case 90:
        return VideoRotation.ROTATION_90;
      case 180:
        return VideoRotation.ROTATION_180;
      case 270:
        return VideoRotation.ROTATION_270;
      default:
        return VideoRotation.ROTATION_0;
    }
  }

  /**
   * Parses the audio-track flag from media metadata.
   *
   * @param value The metadata audio-track flag.
   *
   * @returns True if the file has an available audio track.
   */
  private resolveHasAudio(
    value?: string
  ): boolean {
    const normalizedValue: string = value?.trim().toLowerCase() ?? '';
    return normalizedValue.length > 0 &&
      normalizedValue !== 'false' &&
      normalizedValue !== '0' &&
      normalizedValue !== 'no';
  }

}
