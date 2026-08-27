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

const DEFAULT_VIDEO_FRAME_RATE: number = 24;

export type MediaSourceAudioFrameListener = (frame: AudioFrame) => void;

/** 保存本地媒体文件的音视频元数据。 */
class MediaSourceMetadata {

  readonly width: number;
  readonly height: number;
  readonly rotation: VideoRotation;
  readonly durationUs: number;
  readonly hasAudio: boolean;

  /**
   * 创建媒体文件元数据。
   *
   * @param width 原始视频宽度。
   * @param height 原始视频高度。
   * @param rotation 视频源旋转方向。
   * @param durationUs 媒体文件时长，单位为微秒。
   * @param hasAudio 媒体文件是否包含可用音轨。
   */
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

/** 协调本地媒体文件的音视频解码、同步和循环输出。 */
export class MediaSourceController implements MediaSourceControlling {

  // 基础层组件
  private readonly audioManager: AudioManaging;

  // 服务层组件
  private readonly mediaService: MediaServicing;

  // 媒体层组件
  private readonly videoSourceController: VideoSourceControlling;
  private readonly audioSourceController: AudioSourceControlling;

  // 媒体文件资源
  private metadata: MediaSourceMetadata | null = null;

  /**
   * 创建媒体源 Controller。
   *
   * @param mediaService 提供模型输入尺寸计算能力的媒体 Service。
   * @param audioManager 提供外部音频播放和推送能力的音频 Manager。
   * @param videoFrameListener 视频帧输出监听器。
   * @param audioFrameListener 音频帧输出监听器。
   * @param errorListener 媒体源错误监听器。
   */
  constructor(
    mediaService: MediaServicing,
    audioManager: AudioManaging,
    videoFrameListener: VideoSourceFrameListener,
    audioFrameListener: MediaSourceAudioFrameListener,
    errorListener: VideoSourceErrorListener
  ) {
    // 基础层组件
    this.audioManager = audioManager;

    // 服务层组件
    this.mediaService = mediaService;

    // 媒体层组件
    this.videoSourceController = new VideoSourceController(
      videoFrameListener,
      errorListener
    );
    this.audioSourceController = new AudioSourceController(
      (frame: AudioFrame): void => {
        this.audioManager.write(frame);
        audioFrameListener(frame);
      },
      errorListener
    );
  }

  /**
   * 获取当前媒体文件是否包含可用音轨。
   *
   * @returns 当前媒体文件包含可用音轨时返回 true，否则返回 false。
   */
  get hasAudio(): boolean {
    return this.metadata?.hasAudio ?? false;
  }

  /**
   * 读取本地媒体文件信息并配置音视频源。
   *
   * @param filePath 本地媒体文件路径。
   * @param videoFormat 期望的视频输出格式；未传入时根据文件信息自动计算。
   * @returns 文件实际使用的媒体源配置。
   */
  async prepare(
    filePath: string,
    videoFormat?: RealtimeVideoFormat
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
      resolvedFormat.fps
    );
    if (metadata.hasAudio) {
      this.audioSourceController.configure(filePath);
    }

    this.metadata = metadata;
    return new MediaSourceConfiguration(
      resolvedFormat,
      metadata.hasAudio
    );
  }

  /**
   * 从文件起点同步输出音频帧和视频帧。
   *
   * @returns 媒体源启动完成后的 Promise。
   */
  async start(): Promise<void> {
    const metadata: MediaSourceMetadata = this.requireMetadata();

    if (metadata.hasAudio) {
      await this.audioManager.start();
    }

    const timeline = new MediaTimeline(0, metadata.durationUs);
    try {
      this.videoSourceController.start(timeline);
      if (metadata.hasAudio) {
        this.audioSourceController.start(timeline);
      }
    } catch (error) {
      this.videoSourceController.stop();
      this.audioSourceController.stop();
      await this.audioManager.stop();
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
    this.audioManager.setPlaybackEnabled(enabled);
  }

  /**
   * 停止音视频输出并清理媒体文件状态。
   *
   * @returns 媒体源停止完成后的 Promise。
   */
  async stop(): Promise<void> {
    this.videoSourceController.stop();
    this.audioSourceController.stop();
    await this.stopAudioPlayback();

    this.metadata = null;
  }

  /**
   * 获取已准备的媒体文件元数据。
   *
   * @returns 当前媒体文件元数据。
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
   * 安全停止本地音频播放并记录停止错误。
   *
   * @returns 停止处理完成后的 Promise。
   */
  private async stopAudioPlayback(): Promise<void> {
    try {
      await this.audioManager.stop();
    } catch (error) {
      const reason: string = error instanceof Error ? error.message : String(error);
      XmaxLogger.error(
        `释放本地音频播放器失败\n└─ 原因：${reason}`,
        'Audio'
      );
    }
  }

  /**
   * 读取本地媒体文件的视频尺寸、旋转、时长和音轨信息。
   *
   * @param filePath 本地媒体文件路径。
   * @returns 解析后的媒体文件元数据。
   */
  private async readMetadata(filePath: string): Promise<MediaSourceMetadata> {
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
          `释放视频元数据读取器失败\n└─ 原因：${reason}`,
          'Video'
        );
      } finally {
        fileIo.closeSync(sourceFile);
      }
    }
  }

  /**
   * 根据文件显示尺寸和期望格式解析模型输入视频格式。
   *
   * @param metadata 媒体文件元数据。
   * @param videoFormat 期望的视频输出格式。
   * @returns 适配模型输入尺寸后的实际视频格式。
   */
  private resolveVideoFormat(
    metadata: MediaSourceMetadata,
    videoFormat?: RealtimeVideoFormat
  ): RealtimeVideoFormat {
    const displaySize: ImageSize = this.displaySize(metadata);
    const requestedFormat: RealtimeVideoFormat = videoFormat ?? new RealtimeVideoFormat(
      displaySize.width,
      displaySize.height,
      DEFAULT_VIDEO_FRAME_RATE
    );
    requestedFormat.validate();

    const targetSize: ImageSize = this.mediaService.resolveModelInputSize(
      new ImageSize(requestedFormat.width, requestedFormat.height)
    );

    return new RealtimeVideoFormat(
      targetSize.width,
      targetSize.height,
      requestedFormat.fps
    );
  }

  /**
   * 根据视频旋转方向计算文件的显示尺寸。
   *
   * @param metadata 媒体文件元数据。
   * @returns 考虑旋转方向后的显示尺寸。
   */
  private displaySize(metadata: MediaSourceMetadata): ImageSize {
    if (metadata.rotation === VideoRotation.ROTATION_90 ||
      metadata.rotation === VideoRotation.ROTATION_270) {
      return new ImageSize(metadata.height, metadata.width);
    }

    return new ImageSize(metadata.width, metadata.height);
  }

  /**
   * 将媒体元数据中的角度转换为统一视频旋转方向。
   *
   * @param value 媒体元数据中的旋转角度。
   * @returns 规范化后的视频旋转方向。
   */
  private resolveRotation(value?: string): VideoRotation {
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
   * 解析媒体元数据中的音轨存在标记。
   *
   * @param value 媒体元数据中的音轨标记。
   * @returns 文件包含可用音轨时返回 true，否则返回 false。
   */
  private resolveHasAudio(value?: string): boolean {
    const normalizedValue: string = value?.trim().toLowerCase() ?? '';
    return normalizedValue.length > 0 &&
      normalizedValue !== 'false' &&
      normalizedValue !== '0' &&
      normalizedValue !== 'no';
  }

}
