import { RemoteStream } from '../foundation/rtc/RemoteStream';
import { XmaxError } from '../foundation/errors/XmaxError';
import { InteractionControlling } from '../media/interaction/InteractionControlling';
import { RealtimeVideoTrack } from '../service/realtime/RealtimeVideoTrack';

/** 定义渲染层向 Core 暴露的统一能力。 */
export interface RenderControlling {

  /**
   * 更新当前需要渲染的远端 RTC 视频流。
   *
   * @param stream 远端视频流；传入空值时清除当前流。
   * @returns 无返回值。
   */
  setRemoteStream(stream: RemoteStream | null): void;

  /** 等待本次 SEI 匹配后出现的首个可用远端帧，超时或流被清除时拒绝。 */
  waitUntilRemoteFrameReady(): Promise<void>;

  /** 使启动期间的异步致命错误立即结束首帧等待。 */
  failRemoteFrameWait(error: XmaxError): void;

  /**
   * 为远端视频轨道注册画面和轨迹交互绑定。
   *
   * @param track 需要注册的远端视频轨道。
   * @param interactionController 接收轨迹交互输入的统一媒体组件。
   * @returns 无返回值。
   */
  registerRemoteTrack(
    track: RealtimeVideoTrack,
    interactionController: InteractionControlling
  ): void;

  /**
   * 注销远端轨道的所有渲染绑定并重置远端画面。
   *
   * @param track 需要注销的远端视频轨道；传入空值时仅重置画面。
   * @returns 无返回值。
   */
  resetRemoteTrack(track: RealtimeVideoTrack | null): void;
}
