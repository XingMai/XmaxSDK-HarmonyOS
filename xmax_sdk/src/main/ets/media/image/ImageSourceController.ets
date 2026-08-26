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

const DEFAULT_IMAGE_FRAME_RATE: number = 24;

/** 将本地图片处理为目标尺寸，并按固定帧率持续输出视频帧。 */
export class ImageSourceController implements ImageSourceControlling {

  // 基础层组件
  private readonly imageManager: ImageManaging;

  // 服务层组件
  private readonly mediaService: MediaServicing;

  // 图片帧监听器
  private readonly frameListener: ImageSourceFrameListener;
  private readonly errorListener: ImageSourceErrorListener;

  // 图片帧资源
  private frameFormat: VideoFormat | null = null;
  private framePlane: VideoFramePlane | null = null;
  private videoFormat: RealtimeVideoFormat | null = null;

  // 运行状态
  private frameTimer: number = -1;

  /**
   * 创建图片源 Controller。
   *
   * @param imageManager 提供图片解码能力的图片 Manager。
   * @param mediaService 提供图片尺寸处理能力的媒体 Service。
   * @param frameListener 视频帧输出监听器。
   * @param errorListener 图片源错误监听器。
   */
  constructor(
    imageManager: ImageManaging,
    mediaService: MediaServicing,
    frameListener: ImageSourceFrameListener,
    errorListener: ImageSourceErrorListener
  ) {
    // 基础层组件
    this.imageManager = imageManager;

    // 服务层组件
    this.mediaService = mediaService;

    // 图片帧监听器
    this.frameListener = frameListener;
    this.errorListener = errorListener;
  }

  /**
   * 加载图片并准备可重复输出的视频帧数据。
   *
   * @param source 本地文件路径、图片编码数据或平台 PixelMap。
   * @param videoFormat 期望的视频输出格式；未传入时根据图片尺寸自动计算。
   * @returns 图片实际使用的视频输出格式。
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
        new ImageSize(decodedImage.width, decodedImage.height),
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
   * 将公开图片输入收敛为 SDK 内部已解码图片。
   *
   * @param source 本地文件路径、图片编码数据或平台 PixelMap。
   * @returns 由 SDK 持有的已解码图片。
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

  /**
   * 按目标帧率持续输出准备好的图片帧。
   *
   * @returns 无返回值。
   */
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
    this.frameTimer = setInterval((): void => {
      try {
        this.emitFrame();
      } catch (error) {
        const reason: string = error instanceof Error ? error.message : String(error);
        this.errorListener(reason);
      }
    }, 1000 / videoFormat.fps);
  }

  /**
   * 停止图片帧输出并清理已准备的帧数据。
   *
   * @returns 无返回值。
   */
  stop(): void {
    if (this.frameTimer >= 0) {
      clearInterval(this.frameTimer);
      this.frameTimer = -1;
    }

    this.frameFormat = null;
    this.framePlane = null;
    this.videoFormat = null;
  }

  /**
   * 使用当前时间戳输出一帧图片视频帧。
   *
   * @returns 无返回值。
   */
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
   * 根据图片尺寸和期望格式解析模型输入视频格式。
   *
   * @param sourceSize 原始图片尺寸。
   * @param videoFormat 期望的视频输出格式。
   * @returns 校验并适配后的实际视频格式。
   */
  private resolveVideoFormat(
    sourceSize: ImageSize,
    videoFormat?: RealtimeVideoFormat
  ): RealtimeVideoFormat {
    const requestedFormat: RealtimeVideoFormat = videoFormat ??
      new RealtimeVideoFormat(
        sourceSize.width,
        sourceSize.height,
        DEFAULT_IMAGE_FRAME_RATE
      );
    if (!Number.isFinite(requestedFormat.fps) || requestedFormat.fps <= 0) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Image stream frame rate must be a finite number greater than zero'
      );
    }

    const targetSize: ImageSize = this.mediaService.resolveModelInputSize(
      new ImageSize(requestedFormat.width, requestedFormat.height)
    );

    const resolvedFormat: RealtimeVideoFormat = new RealtimeVideoFormat(
      targetSize.width,
      targetSize.height,
      requestedFormat.fps
    );
    resolvedFormat.validate();

    return resolvedFormat;
  }

}
