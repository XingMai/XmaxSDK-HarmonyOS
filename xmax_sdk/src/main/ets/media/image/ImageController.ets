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

/** 协调本地图片解码、循环帧输出、编码和预览资源。 */
export class ImageController {

  // 基础层组件
  private readonly rtcManager: RtcManaging;
  private readonly imageManager: ImageManaging;

  // 服务层组件
  private readonly mediaService: MediaServicing;

  // 业务层组件
  private readonly imageSourceController: ImageSourceControlling;
  private readonly streamController: StreamControlling;

  // 本地资源
  private activeTrack: RealtimeVideoTrack | null = null;

  /**
   * 创建图片媒体 Controller。
   *
   * @param rtcManager 外部视频源和本地渲染使用的 RTC 基础能力。
   * @param streamController 提供编码配置和视频帧传输能力的统一流组件。
   * @param errorListener 持续图片帧输出错误监听器。
   */
  constructor(
    rtcManager: RtcManaging,
    streamController: StreamControlling,
    errorListener: (error: XmaxError) => void
  ) {
    // 基础层组件
    this.rtcManager = rtcManager;
    this.imageManager = new ImageManager();

    // 服务层组件
    this.mediaService = new MediaService();

    // 业务层组件
    this.streamController = streamController;
    this.imageSourceController = new ImageSourceController(
      this.imageManager,
      this.mediaService,
      (frame: VideoFrame): void => {
        this.streamController.pushLocalVideoFrame(frame);
      },
      (message: string): void => {
        errorListener(new XmaxError(
          XmaxErrorCode.MEDIA_ERROR,
          message
        ));
      }
    );
  }

  /** @returns 当前活动的本地图片视频轨道；尚未创建时返回空值。 */
  get currentTrack(): RealtimeVideoTrack | null {
    return this.activeTrack;
  }

  /**
   * 从图片输入创建持续输出帧的媒体流。
   *
   * @param source 本地文件路径、图片编码数据或平台 PixelMap。
   * @param videoFormat 可选的视频输出格式；未传入时根据图片信息计算。
   * @returns 创建完成后的本地图片媒体流。
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
   * 停止图片帧输出并释放本地预览绑定。
   *
   * @returns 停止操作完成后的 Promise。
   */
  async stopLocalImageStream(): Promise<void> {
    const track: RealtimeVideoTrack | null = this.activeTrack;
    this.activeTrack = null;
    this.imageSourceController.stop();

    if (track !== null) {
      VideoRenderRegistry.unregister(track);
      this.rtcManager.unbindLocalVideo();
    }
  }

  /**
   * 准备图片帧来源并装配编码、传输和预览资源。
   *
   * @param source 本地文件路径、图片编码数据或平台 PixelMap。
   * @param videoFormat 可选的视频输出格式。
   * @returns 完成底层资源装配后的本地图片媒体流。
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
      track = new RealtimeVideoTrack('video0', resolvedFormat);

      this.streamController.setVideoEncoderConfig(resolvedFormat);
      this.rtcManager.useExternalVideoSource();

      this.registerPreview(track);
      this.imageSourceController.start();
      this.activeTrack = track;

      return new RealtimeMediaStream(StreamId.LOCAL, track);
    } catch (error) {
      this.imageSourceController.stop();

      if (track !== null) {
        VideoRenderRegistry.unregister(track);
      }

      throw XmaxError.from(error);
    }
  }

  /**
   * 为本地图片轨道注册 RTC 预览绑定。
   *
   * @param track 需要显示的本地图片视频轨道。
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
