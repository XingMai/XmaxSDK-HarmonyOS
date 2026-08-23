import { RemoteStream } from '../../foundation/rtc/RemoteStream';
import { RtcProviding } from '../../foundation/rtc/RtcProviding';
import { VideoContentMode } from '../../foundation/media/video/VideoContentMode';
import { RemoteVideoControlling } from './RemoteVideoControlling';

/** 管理远端视频流与渲染容器之间的绑定关系。 */
export class RemoteVideoController implements RemoteVideoControlling {

  // 基础层组件
  private readonly rtcProvider: RtcProviding;

  // 渲染资源
  private remoteStream: RemoteStream | null = null;
  private remoteViewId: string = '';
  private remoteContentMode: VideoContentMode = VideoContentMode.FIT;

  /**
   * 创建远端视频渲染 Controller。
   *
   * @param rtcProvider 提供远端视频绑定能力的 RTC Provider。
   */
  constructor(rtcProvider: RtcProviding) {
    this.rtcProvider = rtcProvider;
  }

  /**
   * 更新当前需要渲染的远端视频流。
   *
   * @param stream 远端视频流；传入空值时清除当前流。
   * @returns 无返回值。
   */
  setRemoteStream(stream: RemoteStream | null): void {
    const previousStream: RemoteStream | null = this.remoteStream;
    if (previousStream !== null && previousStream !== stream) {
      this.rtcProvider.unbindRemoteVideo(previousStream);
    }

    this.remoteStream = stream;
    if (stream === null || this.remoteViewId.length === 0) {
      return;
    }

    this.rtcProvider.bindRemoteVideo(
      stream,
      this.remoteViewId,
      this.remoteContentMode
    );
  }

  /**
   * 将远端视频绑定到指定渲染容器。
   *
   * @param viewId 渲染容器标识。
   * @param contentMode 画面显示模式。
   * @returns 无返回值。
   */
  attach(
    viewId: string,
    contentMode: VideoContentMode
  ): void {
    this.remoteViewId = viewId;
    this.remoteContentMode = contentMode;

    const stream: RemoteStream | null = this.remoteStream;
    if (stream !== null) {
      this.rtcProvider.bindRemoteVideo(stream, viewId, contentMode);
    }
  }

  /**
   * 解除指定渲染容器与远端视频的绑定。
   *
   * @param viewId 渲染容器标识。
   * @returns 无返回值。
   */
  detach(viewId: string): void {
    if (this.remoteViewId !== viewId) {
      return;
    }

    const stream: RemoteStream | null = this.remoteStream;
    if (stream !== null) {
      this.rtcProvider.unbindRemoteVideo(stream);
    }

    this.remoteViewId = '';
  }

  /**
   * 清理远端视频流和渲染绑定。
   *
   * @returns 无返回值。
   */
  reset(): void {
    const stream: RemoteStream | null = this.remoteStream;
    this.remoteStream = null;
    this.remoteViewId = '';
    this.remoteContentMode = VideoContentMode.FIT;

    if (stream !== null) {
      this.rtcProvider.unbindRemoteVideo(stream);
    }
  }
}
