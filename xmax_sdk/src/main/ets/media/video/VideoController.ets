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

/** 协调本地视频文件、音轨、编码、传输和预览资源。 */
export class VideoController {

  // 基础层组件
  private readonly rtcManager: RtcManaging;
  private readonly audioManager: AudioManaging;
  private readonly permissionManager: PermissionManaging;
  private readonly errorListener: (error: XmaxError) => void;

  // 服务层组件
  private readonly mediaService: MediaServicing;

  // 业务层组件
  private readonly mediaSourceController: MediaSourceControlling;
  private readonly streamController: StreamControlling;

  // 本地资源
  private activeTrack: RealtimeVideoTrack | null = null;
  private acceptsFrames: boolean = false;
  private currentPlaybackState: LocalVideoPlaybackState | undefined = undefined;
  private lastVideoFrame: VideoFrame | null = null;
  private lastVideoTimestampUs: number = -1;
  private lastAudioTimestampUs: number = -1;
  private frozenVideoTimer: number = -1;
  private silentAudioTimer: number = -1;
  private readonly silentAudioData: Uint8Array = new Uint8Array(
    AudioFrame.SAMPLES_PER_FRAME * 2
  );

  /**
   * 创建视频媒体 Controller。
   *
   * @param context 申请音频相关权限所需的页面上下文。
   * @param rtcManager 外部媒体源和本地渲染使用的 RTC 基础能力。
   * @param streamController 提供编码配置和音视频帧传输能力的统一流组件。
   * @param errorListener 持续媒体输出错误监听器。
   * @param mediaService 当前模型的媒体输入规则。
   */
  constructor(
    context: common.UIAbilityContext,
    rtcManager: RtcManaging,
    streamController: StreamControlling,
    errorListener: (error: XmaxError) => void,
    mediaService: MediaServicing = new MediaService(),
    videoEndedListener: () => void = (): void => {}
  ) {
    // 基础层组件
    this.rtcManager = rtcManager;
    this.audioManager = new AudioManager();
    this.permissionManager = new PermissionManager(context);
    this.errorListener = errorListener;

    // 服务层组件
    this.mediaService = mediaService;

    // 业务层组件
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

  /** @returns 当前活动的本地视频轨道；尚未创建时返回空值。 */
  get currentTrack(): RealtimeVideoTrack | null {
    return this.activeTrack;
  }

  /** @returns 当前视频文件是否包含并输出音轨。 */
  get hasAudio(): boolean {
    return this.mediaSourceController.hasAudio;
  }

  /** @returns 当前文件视频播放状态；尚未创建视频流时返回空值。 */
  get playbackState(): LocalVideoPlaybackState | undefined {
    return this.currentPlaybackState;
  }

  /**
   * 从本地视频文件创建媒体流。
   *
   * @param filePath 本地视频文件路径。
   * @param videoFormat 可选的视频输出格式；未传入时根据文件信息计算。
   * @returns 创建完成后的本地视频媒体流。
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
   * 停止视频和音频帧输出并释放预览资源。
   *
   * @returns 停止操作完成后的 Promise。
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

  /**
   * 立即阻断文件音视频帧输出并解除本地预览绑定。
   *
   * @returns 无返回值。
   */
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

  /** 暂停文件播放并持续发布最后一帧与静音音频。 */
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

  /** 停止冻结帧发布并从原媒体位置恢复播放。 */
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
   * 启用或暂停本地音频预览，不影响 RTC 音频帧输出。
   *
   * @param enabled 是否播放本地预览音频。
   * @returns 无返回值。
   */
  setLocalAudioPreviewEnabled(enabled: boolean): void {
    this.mediaSourceController.setLocalAudioPreviewEnabled(enabled);
  }

  /** 当前配置的本地视频预览音量。 */
  get localAudioVolume(): number {
    return this.mediaSourceController.localAudioVolume;
  }

  /** 设置本地视频预览音量，未创建媒体源时缓存到后续播放。 */
  async setLocalAudioVolume(volume: number): Promise<void> {
    await this.mediaSourceController.setLocalAudioVolume(volume);
  }

  /**
   * 准备文件媒体来源并装配权限、编码、传输和预览资源。
   *
   * @param filePath 本地视频文件路径。
   * @param videoFormat 可选的视频输出格式。
   * @returns 完成底层资源装配后的本地视频媒体流。
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
      track = new RealtimeVideoTrack('video0', resolvedFormat);

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

      return new RealtimeMediaStream(StreamId.LOCAL, track);
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

  private publishDecodedVideoFrame(frame: VideoFrame): void {
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

  private publishDecodedAudioFrame(frame: AudioFrame): void {
    if (!this.acceptsFrames) {
      return;
    }
    const hasTimestamp: boolean = Number.isFinite(frame.timestampUs);
    const output: AudioFrame = !hasTimestamp || frame.timestampUs > this.lastAudioTimestampUs ? frame :
      new AudioFrame(frame.data, this.lastAudioTimestampUs + 1);
    if (hasTimestamp) {
      this.lastAudioTimestampUs = output.timestampUs;
    }
    this.streamController.pushLocalAudioFrame(output);
  }

  private startFrozenPublishing(): void {
    const track: RealtimeVideoTrack | null = this.activeTrack;
    if (track === null || this.frozenVideoTimer >= 0) {
      return;
    }
    const fps: number = track.videoFormat?.fps ?? 30;
    this.publishFrozenVideoFrame();
    this.frozenVideoTimer = setInterval((): void => {
      this.publishFrozenVideoFrame();
    }, 1000 / fps);

    if (this.hasAudio) {
      this.publishSilentAudioFrame();
      this.silentAudioTimer = setInterval((): void => {
        this.publishSilentAudioFrame();
      }, 10);
    }
  }

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

  private reportPublishingError(error: Object): void {
    this.errorListener(new XmaxError(
      XmaxErrorCode.MEDIA_ERROR,
      XmaxError.from(error).message
    ));
  }

  private resetPlaybackFrames(): void {
    this.lastVideoFrame = null;
    this.lastVideoTimestampUs = -1;
    this.lastAudioTimestampUs = -1;
  }

  /**
   * 为本地视频轨道注册 RTC 预览绑定。
   *
   * @param track 需要显示的本地视频轨道。
   * @returns 无返回值。
   */
  private registerPreview(track: RealtimeVideoTrack): void {
    VideoRenderRegistry.register(track, new VideoRenderBinding(
      this.rtcManager.renderLibraryName(),
      (
        viewId: string,
        contentMode: VideoContentMode
      ): void => {
        this.rtcManager.bindLocalVideo(viewId, contentMode);
      },
      (_viewId: string): void => {
        this.rtcManager.unbindLocalVideo();
      }
    ));
  }

}
