import { image } from '@kit.ImageKit';
import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import { ImageProviding } from '../../foundation/media/image/ImageProviding';
import { VideoFrame } from '../../foundation/media/video/VideoFrame';
import { VideoFramePlane } from '../../foundation/media/video/VideoFramePlane';
import { VideoPixelFormat } from '../../foundation/media/video/VideoPixelFormat';
import { VideoRotation } from '../../foundation/media/video/VideoRotation';
import { ImageSize } from '../../service/media/ImageSize';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import { RealtimeVideoTrack } from '../../service/realtime/RealtimeVideoTrack';
import {
  LocalVideoPreviewControlling,
  PreviewRelease
} from './LocalVideoPreviewControlling';
import { VideoRenderRegistry } from './VideoRenderRegistry';

/** 缓存本地视频首帧，并在等待远端结果时提供冻结预览。 */
export class LocalVideoPreviewController implements LocalVideoPreviewControlling {

  // 基础层组件
  private readonly imageProvider: ImageProviding;

  // 预览资源
  private previewFrame: image.PixelMap | null = null;
  private capturePromise: Promise<void> | null = null;
  private frozenTrack: RealtimeVideoTrack | null = null;
  private targetSize: ImageSize | null = null;

  // 运行状态
  private captureVersion: number = 0;
  private freezeVersion: number = 0;

  /**
   * 创建本地视频预览 Controller。
   *
   * @param imageProvider 提供 PixelMap 裁剪缩放能力的图片 Provider。
   */
  constructor(imageProvider: ImageProviding) {
    this.imageProvider = imageProvider;
  }

  /**
   * 配置冻结预览的目标尺寸。
   *
   * @param videoFormat 本地视频发送使用的视频格式。
   * @returns 无返回值。
   */
  configure(videoFormat: RealtimeVideoFormat): void {
    videoFormat.validate();
    this.targetSize = new ImageSize(
      videoFormat.width,
      videoFormat.height
    );
  }

  /**
   * 异步缓存本地视频的第一帧。
   *
   * @param frame 本地视频输出的视频帧。
   * @returns 无返回值。
   */
  captureFirstFrame(frame: VideoFrame): void {
    if (this.capturePromise !== null) {
      return;
    }

    const captureVersion: number = this.captureVersion;
    this.capturePromise = this.capturePreviewFrame(
      frame,
      captureVersion
    );
  }

  /**
   * 将缓存的首帧设置为指定视频轨道的冻结预览。
   *
   * @param track 需要冻结预览的视频轨道。
   * @returns 解除本次冻结预览的方法。
   */
  freeze(track: RealtimeVideoTrack): PreviewRelease {
    const previousTrack: RealtimeVideoTrack | null = this.frozenTrack;
    if (previousTrack !== null && previousTrack !== track) {
      VideoRenderRegistry.setPreviewFrame(previousTrack, undefined);
    }

    const freezeVersion: number = ++this.freezeVersion;
    this.frozenTrack = track;

    const previewFrame: image.PixelMap | null = this.previewFrame;
    if (previewFrame !== null) {
      VideoRenderRegistry.setPreviewFrame(track, previewFrame);
    }

    return (): void => {
      this.releaseFreeze(track, freezeVersion);
    };
  }

  /**
   * 清理冻结绑定、缓存帧和未完成的首帧捕获任务。
   *
   * @returns 清理完成后的 Promise。
   */
  async reset(): Promise<void> {
    const frozenTrack: RealtimeVideoTrack | null = this.frozenTrack;
    if (frozenTrack !== null) {
      VideoRenderRegistry.setPreviewFrame(frozenTrack, undefined);
    }

    this.frozenTrack = null;
    this.freezeVersion++;
    this.captureVersion++;

    const previewFrame: image.PixelMap | null = this.previewFrame;
    const capturePromise: Promise<void> | null = this.capturePromise;
    this.previewFrame = null;
    this.capturePromise = null;
    this.targetSize = null;

    if (previewFrame !== null) {
      await previewFrame.release();
    }
    if (capturePromise !== null) {
      await capturePromise;
    }
  }

  /**
   * 将视频帧转换为预览图片，并在操作仍有效时保存结果。
   *
   * @param frame 待转换的视频帧。
   * @param captureVersion 本次捕获对应的操作版本。
   * @returns 捕获完成后的 Promise。
   */
  private async capturePreviewFrame(
    frame: VideoFrame,
    captureVersion: number
  ): Promise<void> {
    let pixelMap: image.PixelMap | null = null;

    try {
      pixelMap = await this.createPixelMap(frame);
      if (captureVersion !== this.captureVersion) {
        await pixelMap.release();
        return;
      }

      this.previewFrame = pixelMap;
      const frozenTrack: RealtimeVideoTrack | null = this.frozenTrack;
      if (frozenTrack !== null) {
        VideoRenderRegistry.setPreviewFrame(frozenTrack, pixelMap);
      }
    } catch (error) {
      if (pixelMap !== null) {
        await pixelMap.release();
      }

      const reason: string = error instanceof Error ? error.message : String(error);
      XmaxLogger.error(
        `生成本地视频首帧失败\n└─ 原因：${reason}`,
        'Video'
      );
    }
  }

  /**
   * 将 NV12 视频帧转换为符合预览尺寸的 PixelMap。
   *
   * @param frame 待转换的视频帧。
   * @returns 转换后的预览 PixelMap。
   */
  private async createPixelMap(frame: VideoFrame): Promise<image.PixelMap> {
    if (frame.format.pixelFormat !== VideoPixelFormat.NV12 ||
      frame.planes.length < 2) {
      throw new Error('Local video preview requires an NV12 frame');
    }

    const width: number = frame.format.width;
    const height: number = frame.format.height;
    const data: ArrayBuffer = this.packNv12Frame(frame, width, height);
    const pixelMap: image.PixelMap = await image.createPixelMap(data, {
      size: {
        width: width,
        height: height
      },
      srcPixelFormat: image.PixelMapFormat.NV12,
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      editable: true,
      alphaType: image.AlphaType.PREMUL
    });

    try {
      if (frame.rotation !== VideoRotation.ROTATION_0) {
        await pixelMap.rotate(frame.rotation);
      }

      const targetSize: ImageSize | null = this.targetSize;
      if (targetSize !== null) {
        await this.imageProvider.resizePixelMapToFill(
          pixelMap,
          targetSize.width,
          targetSize.height
        );
      }

      return pixelMap;
    } catch (error) {
      await pixelMap.release();
      const reason: string = error instanceof Error ? error.message : String(error);
      throw new Error(reason);
    }
  }

  /**
   * 将带步长的 NV12 平面紧凑排列为连续内存。
   *
   * @param frame NV12 视频帧。
   * @param width 视频帧宽度。
   * @param height 视频帧高度。
   * @returns 紧凑排列后的 NV12 数据。
   */
  private packNv12Frame(
    frame: VideoFrame,
    width: number,
    height: number
  ): ArrayBuffer {
    const lumaPlane: VideoFramePlane = frame.planes[0];
    const chromaPlane: VideoFramePlane = frame.planes[1];
    const lumaLength: number = width * height;
    const output: Uint8Array = new Uint8Array(lumaLength * 3 / 2);

    this.copyRows(
      lumaPlane,
      output,
      0,
      width,
      height
    );
    this.copyRows(
      chromaPlane,
      output,
      lumaLength,
      width,
      height / 2
    );

    return output.buffer;
  }

  /**
   * 按行复制视频平面并去除源数据步长中的填充字节。
   *
   * @param plane 待复制的视频平面。
   * @param output 目标字节数组。
   * @param outputOffset 目标数组的起始偏移量。
   * @param rowLength 每行需要复制的字节数。
   * @param rowCount 需要复制的行数。
   * @returns 无返回值。
   */
  private copyRows(
    plane: VideoFramePlane,
    output: Uint8Array,
    outputOffset: number,
    rowLength: number,
    rowCount: number
  ): void {
    const source: Uint8Array = new Uint8Array(
      plane.data,
      plane.byteOffset,
      plane.byteLength
    );

    for (let row: number = 0; row < rowCount; row++) {
      const sourceOffset: number = row * plane.stride;
      output.set(
        source.subarray(sourceOffset, sourceOffset + rowLength),
        outputOffset + row * rowLength
      );
    }
  }

  /**
   * 在冻结版本仍匹配时解除指定轨道的冻结预览。
   *
   * @param track 当前冻结的视频轨道。
   * @param freezeVersion 本次冻结对应的操作版本。
   * @returns 无返回值。
   */
  private releaseFreeze(
    track: RealtimeVideoTrack,
    freezeVersion: number
  ): void {
    if (freezeVersion !== this.freezeVersion || this.frozenTrack !== track) {
      return;
    }

    VideoRenderRegistry.setPreviewFrame(track, undefined);
    this.frozenTrack = null;
    this.freezeVersion++;
  }
}
