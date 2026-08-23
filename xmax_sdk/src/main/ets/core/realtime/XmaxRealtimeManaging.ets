import { CameraPosition } from '../../foundation/media/camera/CameraPosition';
import { RealtimeContext } from '../../service/realtime/RealtimeContext';
import { RealtimeErrorListener } from '../../service/realtime/RealtimeError';
import { RealtimeMediaStream } from '../../service/realtime/RealtimeMediaStream';
import { RealtimeNetworkQualityListener } from '../../service/realtime/RealtimeNetworkQuality';
import { RealtimePerformanceAlarmListener } from '../../service/realtime/RealtimePerformanceAlarm';
import {
  RealtimeState,
  RealtimeStateListener
} from '../../service/realtime/RealtimeState';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import { RealtimeConfiguration } from './RealtimeConfiguration';

/** 定义 SDK 对接入方提供的实时媒体与生成控制能力。 */
export interface XmaxRealtimeManaging {

  /** 实时能力配置。 */
  readonly options: RealtimeConfiguration;

  /** 当前实时连接状态。 */
  readonly currentState: RealtimeState;

  /**
   * 设置实时连接状态监听器。
   *
   * @param listener 状态监听器；传入空值时清除监听器。
   * @returns 无返回值。
   */
  setStateListener(listener: RealtimeStateListener | null): void;

  /**
   * 设置实时运行错误监听器。
   *
   * @param listener 错误监听器；传入空值时清除监听器。
   * @returns 无返回值。
   */
  setErrorListener(listener: RealtimeErrorListener | null): void;

  /**
   * 设置实时网络质量监听器。
   *
   * @param listener 网络质量监听器；传入空值时清除监听器。
   * @returns 无返回值。
   */
  setNetworkQualityListener(listener: RealtimeNetworkQualityListener | null): void;

  /**
   * 设置实时性能告警监听器。
   *
   * @param listener 性能告警监听器；传入空值时清除监听器。
   * @returns 无返回值。
   */
  setPerformanceAlarmListener(listener: RealtimePerformanceAlarmListener | null): void;

  /**
   * 创建本地相机流并开始预览。
   *
   * @param videoFormat 本地视频格式。
   * @param position 初始相机位置；未传入时使用前置相机。
   * @returns 本地媒体流。
   */
  createLocalCameraStream(
    videoFormat: RealtimeVideoFormat,
    position?: CameraPosition
  ): Promise<RealtimeMediaStream>;

  /**
   * 将当前本地媒体流替换为相机流。
   *
   * @param videoFormat 本地视频格式。
   * @param position 初始相机位置；未传入时使用前置相机。
   * @returns 替换后的本地媒体流。
   */
  replaceLocalCameraStream(
    videoFormat: RealtimeVideoFormat,
    position?: CameraPosition
  ): Promise<RealtimeMediaStream>;

  /**
   * 停止本地相机流并释放本地预览资源。
   *
   * @returns 停止完成后的 Promise。
   */
  stopLocalCameraStream(): Promise<void>;

  /**
   * 切换前后置相机。
   *
   * @returns 更新相机位置后的本地媒体流。
   */
  switchCamera(): Promise<RealtimeMediaStream>;

  /**
   * 更新本地视频格式。
   *
   * @param videoFormat 本地视频格式。
   * @returns 格式更新完成后的 Promise。
   */
  updateVideoFormat(videoFormat: RealtimeVideoFormat): Promise<void>;

  /**
   * 从设备中的视频文件创建本地媒体流。
   *
   * @param filePath 本地视频文件路径。
   * @param videoFormat 期望的视频输出格式；未传入时根据文件信息自动计算。
   * @returns 可用于建立实时连接的本地媒体流。
   */
  createLocalVideoStream(
    filePath: string,
    videoFormat?: RealtimeVideoFormat
  ): Promise<RealtimeMediaStream>;

  /**
   * 将当前本地媒体流替换为设备中的视频文件流。
   *
   * @param filePath 本地视频文件路径。
   * @param videoFormat 期望的视频输出格式；未传入时根据文件信息自动计算。
   * @returns 替换后的本地媒体流。
   */
  replaceLocalVideoStream(
    filePath: string,
    videoFormat?: RealtimeVideoFormat
  ): Promise<RealtimeMediaStream>;

  /**
   * 停止本地视频文件流并释放本地预览资源。
   *
   * @returns 停止完成后的 Promise。
   */
  stopLocalVideoStream(): Promise<void>;

  /**
   * 从设备中的图片文件创建持续输出视频帧的本地媒体流。
   *
   * @param filePath 本地图片文件路径。
   * @param videoFormat 期望的视频输出格式；未传入时根据图片尺寸自动计算。
   * @returns 可用于建立实时连接的本地媒体流。
   */
  createLocalImageStream(
    filePath: string,
    videoFormat?: RealtimeVideoFormat
  ): Promise<RealtimeMediaStream>;

  /**
   * 将当前本地媒体流替换为设备中的图片文件流。
   *
   * @param filePath 本地图片文件路径。
   * @param videoFormat 期望的视频输出格式；未传入时根据图片尺寸自动计算。
   * @returns 替换后的本地媒体流。
   */
  replaceLocalImageStream(
    filePath: string,
    videoFormat?: RealtimeVideoFormat
  ): Promise<RealtimeMediaStream>;

  /**
   * 停止本地图片流并释放本地预览资源。
   *
   * @returns 停止完成后的 Promise。
   */
  stopLocalImageStream(): Promise<void>;

  /**
   * 使用已有本地流建立实时连接。
   *
   * @param localStream 当前 Manager 创建的本地媒体流。
   * @returns 实时连接建立后的远端媒体流。
   */
  connect(localStream: RealtimeMediaStream): Promise<RealtimeMediaStream>;

  /**
   * 断开实时连接。
   *
   * @returns 断开完成后的 Promise。
   */
  disconnect(): Promise<void>;

  /**
   * 开始生成或更新当前生成条件。
   *
   * @param context 生成条件；首次开始生成时必须传入。
   * @returns 操作完成后的 Promise。
   */
  startGeneration(context?: RealtimeContext): Promise<void>;

  /**
   * 停止当前生成任务。
   *
   * @returns 停止完成后的 Promise。
   */
  stopGeneration(): Promise<void>;
}
