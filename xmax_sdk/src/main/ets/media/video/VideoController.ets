//
//  VideoController.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { common } from '@kit.AbilityKit';
import { AudioFrame } from '../../foundation/media/audio/AudioFrame';
import { AudioManager } from '../../foundation/media/audio/AudioManager';
import { AudioManaging } from '../../foundation/media/audio/AudioManaging';
import {
  XmaxError,
  XmaxErrorCode
} from '../../foundation/errors/XmaxError';
import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import { PermissionManager } from '../../foundation/permissions/PermissionManager';
import { PermissionManaging } from '../../foundation/permissions/PermissionManaging';
import { RtcManaging } from '../../foundation/rtc/RtcManaging';
import { VideoContentMode } from '../../foundation/media/video/VideoContentMode';
import { VideoFrame } from '../../foundation/media/video/VideoFrame';
import { BufferVideoFrame } from '../../foundation/media/video/BufferVideoFrame';
import { MediaSourceConfiguration } from '../../media/MediaSourceConfiguration';
import { MediaSourceController } from '../../media/MediaSourceController';
import { MediaSourceControlling } from '../../media/MediaSourceControlling';
import {
  VideoRenderBinding,
  VideoRenderRegistry
} from '../../rendering/video/VideoRenderRegistry';
import { MediaService } from '../../service/media/MediaService';
import { MediaServicing } from '../../service/media/MediaServicing';
import { RealtimeMediaStream } from '../../service/realtime/RealtimeMediaStream';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import { RealtimeVideoTrack } from '../../service/realtime/RealtimeVideoTrack';
import { LocalVideoPlaybackState } from '../../service/realtime/LocalVideoPlaybackState';
import { StreamControlling } from '../../stream/StreamControlling';
import { StreamId } from '../../stream/StreamId';
import { MediaTimeline } from '../MediaTimeline';

/** Coordinates local video files, audio, encoding, transport, and preview resources. */
export class VideoController {

  // File media, permission, and transport dependencies

  /** The adapter for RTC engine, room, and media services. */
  private readonly rtcManager: RtcManaging;

  /** The player for SDK-managed local PCM preview. */
  private readonly audioManager: AudioManaging;

  /** The manager checking and requesting platform permissions. */
  private readonly permissionManager: PermissionManaging;

  /**
   * Delivers video input or publishing errors.
   *
   * @param error The SDK error ending the wait or media output.
   */
  private readonly errorListener: (
    error: XmaxError
  ) => void;

  // Service components

  /** The service resolving model-specific media dimensions. */
  private readonly mediaService: MediaServicing;

  // Business components

  /** The controller coordinating file decoding and audio/video playback. */
  private readonly mediaSourceController: MediaSourceControlling;

  /** The controller coordinating RTC rooms, streams, and signaling. */
  private readonly streamController: StreamControlling;

  // Local video track and publication state

  /** The local track owned by the current media source. */
  private activeTrack: RealtimeVideoTrack | null = null;

  /** Whether the current source may deliver media frames. */
  private acceptsFrames: boolean = false;

  /** The current local video file playback state. */
  private currentPlaybackState: LocalVideoPlaybackState | undefined = undefined;

  // Video cache and published timestamps

  /** The most recent frame retained for paused publication. */
  private lastVideoFrame: VideoFrame | null = null;

  /** The last submitted video timestamp, in microseconds. */
  private lastVideoTimestampUs: number = -1;

  /** The last submitted audio timestamp, in microseconds. */
  private lastAudioTimestampUs: number = -1;

  // Frozen-frame and silent audio delivery while paused

  /** The timer publishing a frozen frame while paused. */
  private frozenVideoTimer: number = -1;

  /** The timer sending silence while local video is paused. */
  private silentAudioTimer: number = -1;

  /** The reusable silent PCM packet for paused publication. */
  private readonly silentAudioData: Uint8Array = new Uint8Array(
    AudioFrame.SAMPLES_PER_FRAME * 2
  );

  /**
   * Creates a video media controller.
   *
   * @param context The context for audio-related permissions.
   * @param rtcManager The RTC services for external media and local rendering.
   * @param streamController The controller for encoding and audio/video frame transport.
   * @param errorListener The handler for continuous media output failures.
   * @param mediaService The model's media sizing service.
   * @param videoEndedListener The local video playback completion handler.
   */
  constructor(
    context: common.UIAbilityContext,
    rtcManager: RtcManaging,
    streamController: StreamControlling,
    errorListener: (
      error: XmaxError
    ) => void,
    mediaService: MediaServicing = new MediaService(),
    videoEndedListener: () => void = (): void => { }
  ) {
    // Foundation components
    this.rtcManager = rtcManager;
    this.audioManager = new AudioManager();
    this.permissionManager = new PermissionManager(context);
    this.errorListener = errorListener;

    // Service components
    this.mediaService = mediaService;

    // Business components
    this.streamController = streamController;
    this.mediaSourceController = new MediaSourceController(
      this.mediaService,
      this.audioManager,
      (frame: VideoFrame): void => {
        this.publishDecodedVideoFrame(frame);
      },
      (frame: AudioFrame): void => {
        this.publishDecodedAudioFrame(frame);
      },
      (message: string): void => {
        if (!this.acceptsFrames) {
          return;
        }
        errorListener(new XmaxError(
          XmaxErrorCode.MEDIA_ERROR,
          message
        ));
      },
      (): void => {
        if (!this.acceptsFrames || this.activeTrack === null ||
          this.currentPlaybackState === LocalVideoPlaybackState.ENDED) {
          return;
        }

        this.currentPlaybackState = LocalVideoPlaybackState.ENDED;
        this.acceptsFrames = false;
        this.stopFrozenPublishing();
        videoEndedListener();
      }
    );
  }

  /** The current local input track, or null without local media. */
  get currentTrack(): RealtimeVideoTrack | null {
    return this.activeTrack;
  }

  /** Whether the current file source has an available audio track. */
  get hasAudio(): boolean {
    return this.mediaSourceController.hasAudio;
  }

  /** The local video playback state, or undefined before local video creation. */
  get playbackState(): LocalVideoPlaybackState | undefined {
    return this.currentPlaybackState;
  }

  /**
   * Creates a local stream from a video file.
   *
   * @param filePath The local video file path.
   * @param videoFormat The optional output format, resolved from file metadata if omitted.
   * @param loop Whether to loop after file completion.
   *
   * @returns The created local video stream.
   */
  async createLocalVideoStream(
    filePath: string,
    videoFormat?: RealtimeVideoFormat,
    loop: boolean = true
  ): Promise<RealtimeMediaStream> {
    if (this.activeTrack !== null) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Stop the current local video stream before creating another one'
      );
    }

    return this.createStream(
      filePath,
      videoFormat,
      loop
    );
  }

  /**
   * Stops video/audio output and releases preview resources.
   *
   * The Promise fulfills after stopping.
   */
  async stopLocalVideoStream(): Promise<void> {
    const hasAudio: boolean = this.mediaSourceController.hasAudio;
    this.prepareForStop();
    this.activeTrack = null;
    this.currentPlaybackState = undefined;

    await this.mediaSourceController.stop();

    if (hasAudio) {
      try {
        this.rtcManager.stopExternalAudioSource();
      } catch (error) {
        const reason: string = error instanceof Error ? error.message : String(error);
        XmaxLogger.error(
          `${XmaxLogger.localized("停止外部音频源失败 (Failed to Stop External Audio Source)\n└─ 原因：", "停止外部音频源失败 (Failed to Stop External Audio Source)\n└─ Reason: ")}${reason}`,
          'Audio'
        );
      }
    }
  }

  /** Blocks file audio/video delivery and detaches preview immediately. */
  prepareForStop(): void {
    this.acceptsFrames = false;
    this.stopFrozenPublishing();
    this.mediaSourceController.setLocalAudioPreviewEnabled(false);

    const track: RealtimeVideoTrack | null = this.activeTrack;
    if (track !== null) {
      VideoRenderRegistry.unregister(track);
      this.rtcManager.unbindLocalVideo();
    }
  }

  /** Pauses file playback while continuously publishing the last frame and silence. */
  async pauseLocalVideoStream(): Promise<void> {
    if (this.currentPlaybackState === LocalVideoPlaybackState.PAUSE) {
      return;
    }
    if (this.activeTrack === null || this.currentPlaybackState === undefined ||
      this.currentPlaybackState === LocalVideoPlaybackState.ENDED) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Create a local video stream before pausing it'
      );
    }
    if (this.lastVideoFrame === null) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Wait for the first local video frame before pausing it'
      );
    }

    await this.mediaSourceController.pause();
    this.startFrozenPublishing();
    this.currentPlaybackState = LocalVideoPlaybackState.PAUSE;
  }

  /** Stops frozen-frame publication and resumes from the paused media position. */
  resumeLocalVideoStream(): void {
    if (this.currentPlaybackState === LocalVideoPlaybackState.PLAYING) {
      return;
    }
    if (this.activeTrack === null || this.currentPlaybackState === undefined ||
      this.currentPlaybackState === LocalVideoPlaybackState.ENDED) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Create a local video stream before resuming it'
      );
    }

    this.stopFrozenPublishing();
    this.currentPlaybackState = LocalVideoPlaybackState.PLAYING;
    try {
      this.mediaSourceController.resume();
    } catch (error) {
      this.currentPlaybackState = LocalVideoPlaybackState.PAUSE;
      this.startFrozenPublishing();
      throw XmaxError.from(error);
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
    this.mediaSourceController.setLocalAudioPreviewEnabled(enabled);
  }

  /** The configured local file preview volume in 0 to 1; zero mutes and one uses original volume. */
  get localAudioVolume(): number {
    return this.mediaSourceController.localAudioVolume;
  }

  /**
   * Sets local preview volume, caching it before source creation.
   *
   * @param volume A finite volume in 0 to 1; zero mutes, one uses original volume, and the default
   * is 0.45.
   */
  async setLocalAudioVolume(
    volume: number
  ): Promise<void> {
    await this.mediaSourceController.setLocalAudioVolume(volume);
  }

  /**
   * Prepares file media, permissions, encoding, transport, and preview resources.
   *
   * @param filePath The local video file path.
   * @param videoFormat The optional video output format.
   * @param loop Whether to loop after file completion.
   *
   * @returns The local video stream after resource setup.
   */
  private async createStream(
    filePath: string,
    videoFormat?: RealtimeVideoFormat,
    loop: boolean = true
  ): Promise<RealtimeMediaStream> {
    let track: RealtimeVideoTrack | null = null;

    try {
      this.resetPlaybackFrames();

      const sourceConfiguration: MediaSourceConfiguration =
        await this.mediaSourceController.prepare(
          filePath,
          videoFormat,
          loop
        );
      const resolvedFormat: RealtimeVideoFormat = sourceConfiguration.videoFormat;
      track = new RealtimeVideoTrack(
        'video0',
        resolvedFormat
      );

      if (sourceConfiguration.hasAudio) {
        await this.permissionManager.ensureMicrophonePermission();
      }

      this.streamController.setVideoEncoderConfig(resolvedFormat);
      this.rtcManager.useExternalVideoSource();
      if (sourceConfiguration.hasAudio) {
        this.rtcManager.startExternalAudioSource();
      }

      this.registerPreview(track);
      this.acceptsFrames = true;
      await this.mediaSourceController.start();

      this.activeTrack = track;
      this.currentPlaybackState = this.mediaSourceController.hasEnded ?
        LocalVideoPlaybackState.ENDED : LocalVideoPlaybackState.PLAYING;
      if (this.currentPlaybackState === LocalVideoPlaybackState.ENDED) {
        this.acceptsFrames = false;
        this.stopFrozenPublishing();
      }

      return new RealtimeMediaStream(
        StreamId.LOCAL,
        track
      );
    } catch (error) {
      this.acceptsFrames = false;
      this.stopFrozenPublishing();
      this.currentPlaybackState = undefined;
      this.resetPlaybackFrames();

      const hasAudio: boolean = this.mediaSourceController.hasAudio;
      await this.mediaSourceController.stop();

      if (hasAudio) {
        try {
          this.rtcManager.stopExternalAudioSource();
        } catch (audioError) {
          const reason: string = audioError instanceof Error ?
            audioError.message : String(audioError);
          XmaxLogger.error(
            `${XmaxLogger.localized("外部音频源启动回滚失败 (External Audio Startup Rollback Failed)\n└─ 原因：", "外部音频源启动回滚失败 (External Audio Startup Rollback Failed)\n└─ Reason: ")}${reason}`,
            'Audio'
          );
        }
      }

      if (track !== null) {
        VideoRenderRegistry.unregister(track);
      }

      throw XmaxError.from(error);
    }
  }

  /**
   * Caches and submits decoded video with increasing timestamps.
   *
   * @param frame The decoded file video frame to retain for preview and submit to RTC.
   */
  private publishDecodedVideoFrame(
    frame: VideoFrame
  ): void {
    if (!this.acceptsFrames) {
      return;
    }

    const hasTimestamp: boolean = Number.isFinite(frame.timestampUs);
    const output: VideoFrame = !hasTimestamp || frame.timestampUs > this.lastVideoTimestampUs ? frame :
      new BufferVideoFrame(
        frame.format,
        this.lastVideoTimestampUs + 1,
        frame.planes,
        frame.rotation
      );

    this.lastVideoFrame = output;
    if (hasTimestamp) {
      this.lastVideoTimestampUs = output.timestampUs;
    }

    this.streamController.pushLocalVideoFrame(output);
  }

  /**
   * Submits decoded audio on the playback timeline.
   *
   * @param frame The decoded PCM frame to submit to RTC on the file playback timeline.
   */
  private publishDecodedAudioFrame(
    frame: AudioFrame
  ): void {
    if (!this.acceptsFrames) {
      return;
    }

    const hasTimestamp: boolean = Number.isFinite(frame.timestampUs);
    const output: AudioFrame = !hasTimestamp || frame.timestampUs > this.lastAudioTimestampUs ? frame :
      new AudioFrame(
        frame.data,
        this.lastAudioTimestampUs + 1
      );

    if (hasTimestamp) {
      this.lastAudioTimestampUs = output.timestampUs;
    }

    this.streamController.pushLocalAudioFrame(output);
  }

  /** Publishes a frozen frame and silence periodically while paused. */
  private startFrozenPublishing(): void {
    const track: RealtimeVideoTrack | null = this.activeTrack;
    if (track === null || this.frozenVideoTimer >= 0) {
      return;
    }

    const fps: number = track.videoFormat?.fps ?? 30;
    this.publishFrozenVideoFrame();
    this.frozenVideoTimer = setInterval(
      (): void => {
        this.publishFrozenVideoFrame();
      },
      1000 / fps
    );

    if (this.hasAudio) {
      this.publishSilentAudioFrame();
      this.silentAudioTimer = setInterval(
        (): void => {
          this.publishSilentAudioFrame();
        },
        10
      );
    }
  }

  /** Stops frozen-frame and silent audio timers. */
  private stopFrozenPublishing(): void {
    if (this.frozenVideoTimer >= 0) {
      clearInterval(this.frozenVideoTimer);
      this.frozenVideoTimer = -1;
    }
    if (this.silentAudioTimer >= 0) {
      clearInterval(this.silentAudioTimer);
      this.silentAudioTimer = -1;
    }
  }

  /** Repeats the last frame with increasing timestamps to preserve paused transport. */
  private publishFrozenVideoFrame(): void {
    const frame: VideoFrame | null = this.lastVideoFrame;
    if (!this.acceptsFrames || frame === null) {
      return;
    }

    const timestampUs: number = Math.max(
      MediaTimeline.currentTimestampUs(),
      this.lastVideoTimestampUs + 1
    );

    try {
      this.publishDecodedVideoFrame(new BufferVideoFrame(
        frame.format,
        timestampUs,
        frame.planes,
        frame.rotation
      ));
    } catch (error) {
      this.reportPublishingError(error);
    }
  }

  /** Sends a silent PCM frame to preserve the paused audio timeline. */
  private publishSilentAudioFrame(): void {
    if (!this.acceptsFrames || !this.hasAudio) {
      return;
    }

    const timestampUs: number = Math.max(
      MediaTimeline.currentTimestampUs(),
      this.lastAudioTimestampUs + 1
    );

    try {
      this.publishDecodedAudioFrame(new AudioFrame(
        this.silentAudioData,
        timestampUs
      ));
    } catch (error) {
      this.reportPublishingError(error);
    }
  }

  /**
   * Converts frame submission failures into media error notifications.
   *
   * @param error The exception raised while submitting decoded media to RTC.
   */
  private reportPublishingError(
    error: Object
  ): void {
    this.errorListener(new XmaxError(
      XmaxErrorCode.MEDIA_ERROR,
      XmaxError.from(error).message
    ));
  }

  /** Clears cached video and submitted audio/video timestamps. */
  private resetPlaybackFrames(): void {
    this.lastVideoFrame = null;
    this.lastVideoTimestampUs = -1;
    this.lastAudioTimestampUs = -1;
  }

  /**
   * Registers RTC preview for a local video track.
   *
   * @param track The local video track to display.
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
