//
//  RtcManaging.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { RealtimeVideoFrame } from '../../service/realtime/RealtimeVideoFrame';
import { image } from '@kit.ImageKit';
import { AudioFrame } from '../media/audio/AudioFrame';
import { CameraPosition } from '../media/camera/CameraPosition';
import { VideoFrame } from '../media/video/VideoFrame';
import { VideoContentMode } from '../media/video/VideoContentMode';
import { RemoteStream } from './RemoteStream';
import { RoomJoinConfiguration } from './RoomJoinConfiguration';
import { RtcEventListener } from './RtcEventListener';
import { RtcQualityListener } from './RtcQualityListener';
import { VideoEncodingConfiguration } from './VideoEncodingConfiguration';

/**
 * 远端视频首次完成渲染时接收对应媒体流的回调。
 *
 * @param stream 需要绑定或处理的媒体流。
 * @returns 无返回值。
 */
export type RtcRemoteVideoRenderedListener = (stream: RemoteStream) => void;

/**
 * copyFrame 只能在当前 RTC 回调内调用，按需复制帧数据。
 *
 * @param stream 需要绑定或处理的媒体流。
 * @param copyFrame 按需复制当前原生帧的函数；仅可在回调期间调用。
 * @returns 无返回值。
 */
export type RtcRemoteVideoFrameListener = (stream: RemoteStream, copyFrame: () => RealtimeVideoFrame) => void;

/** 定义 RTC 引擎、房间、媒体传输和渲染绑定能力。 */
export interface RtcManaging {

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
   * 将本地视频源切换为外部视频帧。
   *
   * @returns 无返回值。
   */
  useExternalVideoSource(): void;

  /**
   * 选择 RTC 内部音频源并启动麦克风采集，调用前须已取得麦克风权限。
   *
   * @returns 无返回值。
   */
  startMicrophoneCapture(): void;

  /**
   * 停止 RTC 麦克风采集。
   *
   * @returns 无返回值。
   */
  stopMicrophoneCapture(): void;

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
   * 更新远端音频流订阅状态。
   *
   * @param userId 远端用户标识。
   * @param subscribe 是否订阅音频流。
   * @returns 无返回值。
   */
  subscribeRemoteAudio(
    userId: string,
    subscribe: boolean
  ): void;

  /**
   * 设置指定远端用户的音频播放音量。
   *
   * @param userId 远端用户标识。
   * @param volume RTC 音量值，100 表示原始音量。
   * @returns 无返回值。
   */
  setRemoteAudioVolume(
    userId: string,
    volume: number
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
   * 使用 RTC 原生截图；调用方负责释放返回的 PixelMap。
   *
   * @param stream 需要绑定或处理的媒体流。
   * @returns 截图完成后返回由调用方负责释放的 PixelMap；超时或失败时拒绝的 Promise。
   */
  takeRemoteSnapshot(stream: RemoteStream): Promise<image.PixelMap>;

  /**
   * 获取 RTC 渲染库名称。
   *
   * @returns RTC 渲染库名称。
   */
  renderLibraryName(): string;

  /**
   * 监听 RTC 已将远端首帧渲染到视图的事件。
   *
   * @param listener 接收事件的监听器；可空接口传入 null 时清除监听器。
   * @returns 无返回值。
   */
  setRemoteVideoRenderedListener(listener: RtcRemoteVideoRenderedListener | null): void;

  /**
   * 当前发布周期是否曾成功渲染首帧，用于同一流重新挂载视图。
   *
   * @param stream 需要绑定或处理的媒体流。
   * @returns 指定流在当前发布周期已成功渲染首帧时返回 true。
   */
  hasRenderedRemoteVideo(stream: RemoteStream): boolean;

  /**
   * 监听解码及后处理完成的远端帧，不依赖 Surface 是否挂载。
   *
   * @param listener 接收事件的监听器；可空接口传入 null 时清除监听器。
   * @returns 无返回值。
   */
  setRemoteVideoFrameListener(listener: RtcRemoteVideoFrameListener | null): void;

  /**
   * 按需启停远端帧回调；首帧确认后关闭以避免持续传输像素数据到 ArkTS。
   *
   * @param stream 需要绑定或处理的媒体流。
   * @param enabled 是否开启该能力。
   * @returns 无返回值。
   */
  observeRemoteVideoFrames(stream: RemoteStream, enabled: boolean): void;

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
