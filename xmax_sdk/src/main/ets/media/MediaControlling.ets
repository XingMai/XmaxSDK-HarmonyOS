import { image } from '@kit.ImageKit';
import { CameraPosition } from '../foundation/media/camera/CameraPosition';
import { RealtimeCameraPreviewReadyListener } from '../service/realtime/RealtimeCameraPreview';
import { RealtimeMediaStream } from '../service/realtime/RealtimeMediaStream';
import { RealtimeVideoFormat } from '../service/realtime/RealtimeVideoFormat';
import { RealtimeVideoTrack } from '../service/realtime/RealtimeVideoTrack';
import { InteractionControlling } from './interaction/InteractionControlling';

/** 定义媒体层向 Core 暴露的统一能力。 */
export interface MediaControlling extends InteractionControlling {

  /** @returns 当前活动的本地视频轨道；没有媒体来源时返回空值。 */
  readonly currentTrack: RealtimeVideoTrack | null;

  /** @returns 当前本地视频格式；没有活动轨道时返回空值。 */
  readonly currentVideoFormat: RealtimeVideoFormat | undefined;

  /** @returns 当前媒体来源是否包含由 SDK 管理的本地音频。 */
  readonly hasAudio: boolean;

  /**
   * 设置摄像头预览就绪监听器。
   *
   * @param listener 预览就绪监听器；传入空值时清除监听器。
   * @returns 无返回值。
   */
  setCameraPreviewReadyListener(
    listener: RealtimeCameraPreviewReadyListener | null
  ): void;

  /**
   * 创建并持有本地相机媒体流，同时启动采集和本地预览。
   *
   * @param videoFormat 相机采集与 RTC 编码使用的视频格式。
   * @param position 首次启用的摄像头位置。
   * @returns 包含本地相机视频轨道的媒体流。
   */
  createLocalCameraStream(
    videoFormat: RealtimeVideoFormat,
    position: CameraPosition
  ): Promise<RealtimeMediaStream>;

  /**
   * 使用新的采集参数更新当前相机媒体流。
   *
   * @param videoFormat 更新后相机采集与 RTC 编码使用的视频格式。
   * @param position 更新后启用的摄像头位置。
   * @returns 包含更新后本地相机视频轨道的媒体流。
   */
  replaceLocalCameraStream(
    videoFormat: RealtimeVideoFormat,
    position: CameraPosition
  ): Promise<RealtimeMediaStream>;

  /** @returns 当前相机来源停止并释放完成后的 Promise。 */
  stopLocalCameraStream(): Promise<void>;

  /** @returns 前后置摄像头切换完成后的本地媒体流。 */
  switchCamera(): Promise<RealtimeMediaStream>;

  /**
   * 从本地视频文件创建并持有媒体流。
   *
   * @param filePath 可读取的本地视频文件路径。
   * @param videoFormat 可选的目标视频格式；未传入时根据文件信息计算。
   * @returns 包含循环输出文件音视频帧的本地媒体流。
   */
  createLocalVideoStream(
    filePath: string,
    videoFormat?: RealtimeVideoFormat
  ): Promise<RealtimeMediaStream>;

  /** @returns 当前视频文件来源停止并释放完成后的 Promise。 */
  stopLocalVideoStream(): Promise<void>;

  /**
   * 从图片输入创建并持有持续输出帧的媒体流。
   *
   * @param source 本地文件路径、图片编码数据或平台 PixelMap。
   * @param videoFormat 可选的目标视频格式；未传入时根据图片信息计算。
   * @returns 包含持续输出图片帧的本地媒体流。
   */
  createLocalImageStream(
    source: string | ArrayBuffer | Uint8Array | image.PixelMap,
    videoFormat?: RealtimeVideoFormat
  ): Promise<RealtimeMediaStream>;

  /** @returns 当前图片来源停止并释放完成后的 Promise。 */
  stopLocalImageStream(): Promise<void>;

  /**
   * 判断指定媒体流是否由当前活动媒体来源持有。
   *
   * @param stream 需要验证所有权的媒体流。
   * @returns 媒体流的视频轨道由当前活动来源持有时返回 `true`。
   */
  owns(stream: RealtimeMediaStream): boolean;

  /**
   * 启用或暂停文件视频的本地音频预览，不影响 RTC 音频帧输出。
   *
   * @param enabled 是否播放本地预览音频。
   * @returns 无返回值。
   */
  setLocalAudioPreviewEnabled(enabled: boolean): void;
}
