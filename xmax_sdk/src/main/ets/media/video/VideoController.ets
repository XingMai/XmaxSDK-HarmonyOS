import { common } from '@kit.AbilityKit';
import { AudioFrame } from '../../foundation/media/audio/AudioFrame';
import { AudioManager } from '../../foundation/media/audio/AudioManager';
import { AudioManaging } from '../../foundation/media/audio/AudioManaging';
import {
  XmaxError,
  XmaxErrorCode
} from '../../foundation/errors/XmaxError';
import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import { ImageManager } from '../../foundation/media/image/ImageManager';
import { ImageManaging } from '../../foundation/media/image/ImageManaging';
import { PermissionManager } from '../../foundation/permissions/PermissionManager';
import { PermissionManaging } from '../../foundation/permissions/PermissionManaging';
import { RtcManaging } from '../../foundation/rtc/RtcManaging';
import { VideoContentMode } from '../../foundation/media/video/VideoContentMode';
import { VideoFrame } from '../../foundation/media/video/VideoFrame';
import { MediaSourceConfiguration } from '../../media/MediaSourceConfiguration';
import { MediaSourceController } from '../../media/MediaSourceController';
import { MediaSourceControlling } from '../../media/MediaSourceControlling';
import { LocalVideoPreviewController } from '../../rendering/video/LocalVideoPreviewController';
import {
  LocalVideoPreviewControlling,
  PreviewRelease
} from '../../rendering/video/LocalVideoPreviewControlling';
import {
  VideoRenderBinding,
  VideoRenderRegistry
} from '../../rendering/video/VideoRenderRegistry';
import { MediaService } from '../../service/media/MediaService';
import { MediaServicing } from '../../service/media/MediaServicing';
import { RealtimeMediaStream } from '../../service/realtime/RealtimeMediaStream';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import { RealtimeVideoTrack } from '../../service/realtime/RealtimeVideoTrack';
import { StreamId } from '../../transport/stream/StreamId';
import { TransportControlling } from '../../transport/TransportControlling';

/** 协调本地视频文件、音轨、编码、传输和预览资源。 */
export class VideoController {

  // 基础层组件
  private readonly rtcManager: RtcManaging;
  private readonly audioManager: AudioManaging;
  private readonly imageManager: ImageManaging;
  private readonly permissionManager: PermissionManaging;

  // 服务层组件
  private readonly mediaService: MediaServicing;

  // 业务层组件
  private readonly mediaSourceController: MediaSourceControlling;
  private readonly transportController: TransportControlling;
  private readonly localVideoPreviewController: LocalVideoPreviewControlling;

  // 本地资源
  private activeTrack: RealtimeVideoTrack | null = null;

  /**
   * 创建视频媒体 Controller。
   *
   * @param context 申请音频相关权限所需的页面上下文。
   * @param rtcManager 外部媒体源和本地渲染使用的 RTC 基础能力。
   * @param transportController 提供编码配置和音视频帧传输能力的统一组件。
   * @param errorListener 持续媒体输出错误监听器。
   */
  constructor(
    context: common.UIAbilityContext,
    rtcManager: RtcManaging,
    transportController: TransportControlling,
    errorListener: (error: XmaxError) => void
  ) {
    // 基础层组件
    this.rtcManager = rtcManager;
    this.audioManager = new AudioManager();
    this.imageManager = new ImageManager();
    this.permissionManager = new PermissionManager(context);

    // 服务层组件
    this.mediaService = new MediaService();

    // 业务层组件
    this.transportController = transportController;
    this.localVideoPreviewController = new LocalVideoPreviewController(
      this.imageManager
    );
    this.mediaSourceController = new MediaSourceController(
      this.mediaService,
      this.audioManager,
      (frame: VideoFrame): void => {
        this.localVideoPreviewController.captureFirstFrame(frame);
        this.transportController.pushLocalVideoFrame(frame);
      },
      (frame: AudioFrame): void => {
        this.transportController.pushLocalAudioFrame(frame);
      },
      (message: string): void => {
        errorListener(new XmaxError(
          XmaxErrorCode.MEDIA_ERROR,
          message
        ));
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

  /**
   * 从本地视频文件创建媒体流。
   *
   * @param filePath 本地视频文件路径。
   * @param videoFormat 可选的视频输出格式；未传入时根据文件信息计算。
   * @returns 创建完成后的本地视频媒体流。
   */
  async createLocalVideoStream(
    filePath: string,
    videoFormat?: RealtimeVideoFormat
  ): Promise<RealtimeMediaStream> {
    if (this.activeTrack !== null) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Stop the current local video stream before creating another one'
      );
    }

    return this.createStream(
      filePath,
      videoFormat
    );
  }

  /**
   * 停止视频和音频帧输出并释放预览资源。
   *
   * @returns 停止操作完成后的 Promise。
   */
  async stopLocalVideoStream(): Promise<void> {
    const track: RealtimeVideoTrack | null = this.activeTrack;
    const hasAudio: boolean = this.mediaSourceController.hasAudio;
    this.activeTrack = null;
    await this.mediaSourceController.stop();
    await this.localVideoPreviewController.reset();

    if (hasAudio) {
      try {
        this.rtcManager.stopExternalAudioSource();
      } catch (error) {
        const reason: string = error instanceof Error ? error.message : String(error);
        XmaxLogger.error(
          `停止外部音频源失败\n└─ 原因：${reason}`,
          'Audio'
        );
      }
    }

    if (track !== null) {
      VideoRenderRegistry.unregister(track);
      this.rtcManager.unbindLocalVideo();
    }
  }

  /**
   * 将本地视频时间线重置到起点并重新开始帧输出。
   *
   * @returns 重启操作完成后的 Promise。
   */
  async restartForGeneration(): Promise<void> {
    if (this.activeTrack !== null) {
      await this.mediaSourceController.restart();
    }
  }

  /**
   * 将当前本地视频预览冻结在首帧。
   *
   * @returns 解除冻结并恢复预览的回调；没有活动轨道时返回空操作。
   */
  freezePreview(): PreviewRelease {
    const track: RealtimeVideoTrack | null = this.activeTrack;
    if (track === null) {
      return (): void => {};
    }

    return this.localVideoPreviewController.freeze(track);
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
    videoFormat?: RealtimeVideoFormat
  ): Promise<RealtimeMediaStream> {
    let track: RealtimeVideoTrack | null = null;

    try {
      const sourceConfiguration: MediaSourceConfiguration =
        await this.mediaSourceController.prepare(
          filePath,
          videoFormat
        );
      const resolvedFormat: RealtimeVideoFormat = sourceConfiguration.videoFormat;
      track = new RealtimeVideoTrack('video0', resolvedFormat);
      this.localVideoPreviewController.configure(resolvedFormat);

      if (sourceConfiguration.hasAudio) {
        await this.permissionManager.ensureMicrophonePermission();
      }

      this.transportController.setVideoEncoderConfig(resolvedFormat);
      this.rtcManager.useExternalVideoSource();
      if (sourceConfiguration.hasAudio) {
        this.rtcManager.startExternalAudioSource();
      }

      this.registerPreview(track);
      await this.mediaSourceController.start();
      this.activeTrack = track;

      return new RealtimeMediaStream(StreamId.LOCAL, track);
    } catch (error) {
      const hasAudio: boolean = this.mediaSourceController.hasAudio;
      await this.mediaSourceController.stop();
      await this.localVideoPreviewController.reset();

      if (hasAudio) {
        try {
          this.rtcManager.stopExternalAudioSource();
        } catch (audioError) {
          const reason: string = audioError instanceof Error ?
            audioError.message : String(audioError);
          XmaxLogger.error(
            `外部音频源启动回滚失败\n└─ 原因：${reason}`,
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
