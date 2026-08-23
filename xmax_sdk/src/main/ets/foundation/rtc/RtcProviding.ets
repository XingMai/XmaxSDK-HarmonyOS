import { AudioFrame } from '../media/audio/AudioFrame';
import { CameraPosition } from '../media/camera/CameraPosition';
import { VideoFrame } from '../media/video/VideoFrame';
import { VideoContentMode } from '../media/video/VideoContentMode';
import { RemoteStream } from './RemoteStream';
import { RoomJoinConfiguration } from './RoomJoinConfiguration';
import { RtcEventListener } from './RtcEventListener';
import { RtcQualityListener } from './RtcQualityListener';
import { VideoEncodingConfiguration } from './VideoEncodingConfiguration';

/** 定义 RTC 引擎、房间、媒体传输和渲染绑定能力。 */
export interface RtcProviding {

  /**
   * 初始化 RTC 引擎。
   *
   * @returns 初始化完成后的 Promise。
   */
  initialize(): Promise<void>;

  /**
   * 销毁 RTC 引擎并释放资源。
   *
   * @returns 资源释放完成后的 Promise。
   */
  destroy(): Promise<void>;

  /**
   * 应用视频编码配置。
   *
   * @param configuration 视频编码配置。
   * @returns 无返回值。
   */
  configureVideoEncoding(configuration: VideoEncodingConfiguration): void;

  /**
   * 开启 RTC 内部视频采集。
   *
   * @param width 采集宽度。
   * @param height 采集高度。
   * @param frameRate 采集帧率。
   * @returns 无返回值。
   */
  startVideoCapture(
    width: number,
    height: number,
    frameRate: number
  ): void;

  /**
   * 停止 RTC 内部视频采集。
   *
   * @returns 无返回值。
   */
  stopVideoCapture(): void;

  /**
   * 切换 RTC 内部采集使用的摄像头。
   *
   * @param position 目标摄像头位置。
   * @returns 无返回值。
   */
  switchCamera(position: CameraPosition): void;

  /**
   * 将本地视频源切换为外部视频帧。
   *
   * @returns 无返回值。
   */
  useExternalVideoSource(): void;

  /**
   * 启动 RTC 外部音频源。
   *
   * @returns 无返回值。
   */
  startExternalAudioSource(): void;

  /**
   * 停止 RTC 外部音频源。
   *
   * @returns 无返回值。
   */
  stopExternalAudioSource(): void;

  /**
   * 应用本地视频镜像配置。
   *
   * @param position 相机位置。
   * @returns 无返回值。
   */
  configureLocalVideoMirror(position: CameraPosition): void;

  /**
   * 推送一帧外部视频数据。
   *
   * @param frame 视频帧。
   * @param seiData 随视频帧发送的附加数据。
   * @returns 无返回值。
   */
  pushExternalVideoFrame(
    frame: VideoFrame,
    seiData?: Uint8Array
  ): void;

  /**
   * 推送一帧外部音频数据。
   *
   * @param frame 10ms PCM 音频帧。
   * @returns 无返回值。
   */
  pushExternalAudioFrame(frame: AudioFrame): void;

  /**
   * 加入 RTC 房间。
   *
   * @param configuration 房间加入配置。
   * @returns 加入房间完成后的 Promise。
   */
  joinRoom(configuration: RoomJoinConfiguration): Promise<void>;

  /**
   * 离开当前 RTC 房间。
   *
   * @returns 离开房间完成后的 Promise。
   */
  leaveRoom(): Promise<void>;

  /**
   * 发布本地视频流。
   *
   * @returns 无返回值。
   */
  publishLocalVideo(): void;

  /**
   * 停止发布本地视频流。
   *
   * @returns 无返回值。
   */
  unpublishLocalVideo(): void;

  /**
   * 发布本地音频流。
   *
   * @returns 无返回值。
   */
  publishLocalAudio(): void;

  /**
   * 停止发布本地音频流。
   *
   * @returns 无返回值。
   */
  unpublishLocalAudio(): void;

  /**
   * 更新远端视频流订阅状态。
   *
   * @param userId 远端用户标识。
   * @param subscribe 是否订阅视频流。
   * @returns 无返回值。
   */
  subscribeRemoteVideo(
    userId: string,
    subscribe: boolean
  ): void;

  /**
   * 将本地视频绑定到渲染视图。
   *
   * @param viewId 渲染视图标识。
   * @param contentMode 视频内容显示模式。
   * @returns 无返回值。
   */
  bindLocalVideo(
    viewId: string,
    contentMode: VideoContentMode
  ): void;

  /**
   * 解除本地视频与渲染视图的绑定。
   *
   * @returns 无返回值。
   */
  unbindLocalVideo(): void;

  /**
   * 将远端视频流绑定到渲染视图。
   *
   * @param stream 远端流信息。
   * @param viewId 渲染视图标识。
   * @param contentMode 视频内容显示模式。
   * @returns 无返回值。
   */
  bindRemoteVideo(
    stream: RemoteStream,
    viewId: string,
    contentMode: VideoContentMode
  ): void;

  /**
   * 解除远端视频流与渲染视图的绑定。
   *
   * @param stream 远端流信息。
   * @returns 无返回值。
   */
  unbindRemoteVideo(stream: RemoteStream): void;

  /**
   * 获取 RTC 渲染库名称。
   *
   * @returns RTC 渲染库名称。
   */
  renderLibraryName(): string;

  /**
   * 向当前 RTC 房间发送消息。
   *
   * @param message 消息内容。
   * @returns 无返回值。
   */
  sendRoomMessage(message: string): void;

  /**
   * 设置 RTC 事件监听器。
   *
   * @param listener RTC 事件监听器；传入空值时清除监听器。
   * @returns 无返回值。
   */
  setEventListener(listener: RtcEventListener | null): void;

  /**
   * 设置 RTC 质量事件监听器。
   *
   * @param listener RTC 质量事件监听器；传入空值时清除监听器。
   * @returns 无返回值。
   */
  setQualityListener(listener: RtcQualityListener | null): void;
}
