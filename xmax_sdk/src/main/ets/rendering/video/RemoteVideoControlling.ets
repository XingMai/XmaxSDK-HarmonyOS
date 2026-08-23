import { RemoteStream } from '../../foundation/rtc/RemoteStream';
import { VideoContentMode } from '../../foundation/media/video/VideoContentMode';

/** 定义远端视频流的渲染绑定能力。 */
export interface RemoteVideoControlling {

  /**
   * 设置当前远端视频流。
   *
   * @param stream 远端视频流；传入空值时清除当前流。
   * @returns 无返回值。
   */
  setRemoteStream(
    stream: RemoteStream | null
  ): void;

  /**
   * 将远端视频绑定到渲染容器。
   *
   * @param viewId 渲染容器标识。
   * @param contentMode 画面显示模式。
   * @returns 无返回值。
   */
  attach(
    viewId: string,
    contentMode: VideoContentMode
  ): void;

  /**
   * 解除远端视频与渲染容器的绑定。
   *
   * @param viewId 渲染容器标识。
   * @returns 无返回值。
   */
  detach(
    viewId: string
  ): void;

  /**
   * 清理远端视频流和渲染绑定。
   *
   * @returns 无返回值。
   */
  reset(): void;
}
