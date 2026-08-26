import { CameraPosition } from '../foundation/media/camera/CameraPosition';
import { PreviewRelease } from '../rendering/video/LocalVideoPreviewControlling';
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
   * 使用新的采集参数将当前本地媒体来源替换为相机流。
   *
   * @param videoFormat 替换后相机采集与 RTC 编码使用的视频格式。
   * @param position 替换后启用的摄像头位置。
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

  /**
   * 使用本地视频文件替换当前本地媒体来源。
   *
   * @param filePath 可读取的本地视频文件路径。
   * @param videoFormat 可选的目标视频格式；未传入时根据文件信息计算。
   * @returns 包含替换后文件视频轨道的本地媒体流。
   */
  replaceLocalVideoStream(
    filePath: string,
    videoFormat?: RealtimeVideoFormat
  ): Promise<RealtimeMediaStream>;

  /** @returns 当前视频文件来源停止并释放完成后的 Promise。 */
  stopLocalVideoStream(): Promise<void>;

  /**
   * 从本地图片文件创建并持有持续输出帧的媒体流。
   *
   * @param filePath 可读取的本地图片文件路径。
   * @param videoFormat 可选的目标视频格式；未传入时根据图片信息计算。
   * @returns 包含持续输出图片帧的本地媒体流。
   */
  createLocalImageStream(
    filePath: string,
    videoFormat?: RealtimeVideoFormat
  ): Promise<RealtimeMediaStream>;

  /**
   * 使用本地图片文件替换当前本地媒体来源。
   *
   * @param filePath 可读取的本地图片文件路径。
   * @param videoFormat 可选的目标视频格式；未传入时根据图片信息计算。
   * @returns 包含替换后图片视频轨道的本地媒体流。
   */
  replaceLocalImageStream(
    filePath: string,
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
   * 冻结当前文件视频的本地预览。
   *
   * @returns 解除预览冻结的回调；非视频来源返回空操作。
   */
  freezePreview(): PreviewRelease;

  /** @returns 当前文件媒体从起点重新播放完成后的 Promise。 */
  restartForGeneration(): Promise<void>;
}
