import { RealtimeVideoFrameListener } from '../../service/realtime/RealtimeVideoFrame';
import { image } from '@kit.ImageKit';
import { CameraPosition } from '../../foundation/media/camera/CameraPosition';
import { RealtimeContext } from '../../service/realtime/RealtimeContext';
import { RealtimeMediaStream } from '../../service/realtime/RealtimeMediaStream';
import { RealtimeNetworkQualityListener } from '../../service/realtime/RealtimeNetworkQuality';
import { RealtimePerformanceAlarmListener } from '../../service/realtime/RealtimePerformanceAlarm';
import {
  RealtimeReason,
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

  /** 当前配置的本地视频预览音量（0～1），默认 0.45；不受生成期间自动静音影响。 */
  readonly localAudioVolume: number;

  /** 当前远端播放音量（0～1），按 RTC 百分比精度返回；新建相机/图片流后为 0，视频流后为 1。 */
  readonly remoteAudioVolume: number;

  /**
   * 设置实时生命周期状态监听器，包含本地准备、预览就绪及 state.reason 中的结束/失败原因。
   *
   * @param listener 状态监听器；传入空值时清除监听器。
   * @returns 无返回值。
   */
  setStateListener(listener: RealtimeStateListener | null): void;

  /**
   * 异步交付当前生成流的 RTC 后处理帧；null 取消监听，未监听时不复制像素。
   * 缓冲区可在回调后持有；仅保留最新待交付帧，不保证逐帧交付。
   * 回调运行在 ArkTS 事件循环中，耗时处理应移交 Worker。
   * 断开后停止交付，监听器配置保留以供后续生成使用。
   */
  setRemoteVideoFrameListener(listener: RealtimeVideoFrameListener | null): void;


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
   * 设置本地视频文件的预览音量，不影响上传的音频和生成期间的自动静音。
   * 可在创建本地流前设置，停止或替换视频后保留。
   * @param volume 0～1 的有限数值；0 为静音，1 为原始音量，默认 0.45。
   * @returns 设置完成后的 Promise；无效参数或设置失败时拒绝 Promise。
   */
  setLocalAudioVolume(volume: number): Promise<void>;

  /**
   * 设置远端生成结果的播放音量，后续订阅和重连沿用该值。
   * 新建相机/图片流成功后重置为 0，新建视频流成功后重置为 1；自定义音量请在创建流后设置。
   * @param volume 0～1 的有限数值；0 为静音，1 为原始音量；尚未创建本地流时为 1。
   * @returns 设置完成后的 Promise；无效参数或设置失败时拒绝 Promise。
   */
  setRemoteAudioVolume(volume: number): Promise<void>;


  /**
   * 创建本地相机流并开始预览；返回轨道供视图绑定，有效帧和预览绑定完成后进入 READY。
   *
   * @param videoFormat 本地视频格式；省略时使用当前模型默认相机规格。
   * @param position 初始相机位置；未传入时使用前置相机。
   * @param useMicrophone 是否启用麦克风，默认 false；创建时申请权限，连接时开始采集，断开时停止。
   * @returns 本地媒体流。
   */
  createLocalCameraStream(
    videoFormat?: RealtimeVideoFormat,
    position?: CameraPosition,
    useMicrophone?: boolean
  ): Promise<RealtimeMediaStream>;

  /**
   * 停止本地相机流并释放本地预览资源。
   *
   * @returns 停止完成后的 Promise。
   */
  stopLocalCameraStream(): Promise<void>;

  /**
   * 切换前后置相机。生成期间会停止当前任务并使用缓存条件恢复，保留 RTC 连接。
   * 连接或生成启动期间不可切换。
   *
   * @returns 更新相机位置后的本地媒体流。
   */
  switchCamera(): Promise<RealtimeMediaStream>;

  /**
   * 从设备中的视频文件创建本地媒体流。
   *
   * @param filePath 本地视频文件路径。
   * @param videoFormat 期望的视频输出格式；未传入时按文件显示尺寸计算模型输入尺寸，并使用模型默认帧率；显式指定时保留帧率。
   * @returns 可用于建立实时连接的本地媒体流。
   * @throws 输出尺寸不符合模型规则时返回 INVALID_CONFIGURATION 错误。
   */
  createLocalVideoStream(
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
   * 从图片输入创建持续输出视频帧的本地媒体流。
   *
   * @param source 本地文件路径、图片编码数据或平台 PixelMap。
   * @param videoFormat 期望的视频输出格式；未传入时按图片尺寸计算模型输入尺寸，并使用模型默认帧率；显式指定时保留帧率。
   * @returns 可用于建立实时连接的本地媒体流。
   * @throws 输出尺寸不符合模型规则时返回 INVALID_CONFIGURATION 错误。
   */
  createLocalImageStream(
    source: string | ArrayBuffer | Uint8Array | image.PixelMap,
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
   * 断开实时连接并保留当前本地媒体流和预览。
   * 取消正在进行的连接和生成；清理完成后通过 state.reason 返回原因。
   * 尚未连接且没有相关操作时直接返回，不改变本地准备或预览状态。
   *
   * @param reason 本次断开的原因；省略时为 RealtimeReason.NORMAL。
   * @returns 受影响的操作结束、会话回滚和连接清理完成后的 Promise。
   */
  disconnect(reason?: RealtimeReason): Promise<void>;

  /**
   * 关闭当前实时生命周期并释放本地媒体、连接和 RTC Engine。
   *
   * 调用后会立即停止媒体推帧并解绑视频渲染，剩余资源在返回的 Promise 中异步释放。
   *
   * @returns 全部实时资源释放完成后的 Promise；重复调用时返回同一个关闭任务。
   */
  close(): Promise<void>;

  /**
   * 开始生成或更新当前生成条件。
   *
   * @param context 生成条件；首次开始生成时必须传入。
   * @returns 操作完成后的 Promise。
   */
  startGeneration(context?: RealtimeContext): Promise<void>;

  /**
   * 使用当前本地流按需连接并开始生成；已经连接时复用连接，生成中更新条件。
   *
   * @param localStream 当前 Manager 创建并持有的本地媒体流。
   * @param context 首次生成必须提供；同一连接内可省略以复用缓存条件。
   * @returns 生成开始后的远端媒体流，可交给组合视频组件显示。
   */
  startGeneration(
    localStream: RealtimeMediaStream,
    context?: RealtimeContext
  ): Promise<RealtimeMediaStream>;
}
