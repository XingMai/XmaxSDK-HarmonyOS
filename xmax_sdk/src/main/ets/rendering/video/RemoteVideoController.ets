//
//  RemoteVideoController.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { RemoteStream } from '../../foundation/rtc/RemoteStream';
import { RtcManaging } from '../../foundation/rtc/RtcManaging';
import { VideoContentMode } from '../../foundation/media/video/VideoContentMode';
import { RemoteVideoControlling } from './RemoteVideoControlling';

/** 管理远端视频流与渲染容器之间的绑定关系。 */
export class RemoteVideoController implements RemoteVideoControlling {

  /** 平台渲染与就绪通知 */
  private readonly rtcManager: RtcManaging;

  /** 渲染资源 */
  /**
   * 通知远端画面是否已具备显示条件。
   *
   * @param ready 视频画面是否已经可见。
   * @returns 无返回值。
   */
  private readonly readinessListener: (ready: boolean) => void;

  /** 当前远端流和视图配置 */
  private remoteStream: RemoteStream | null = null;
  private remoteViewId: string = '';
  private remoteContentMode: VideoContentMode = VideoContentMode.FIT;

  /**
   * 创建远端视频渲染 Controller。
   *
   * @param rtcManager 提供远端视频绑定能力的 RTC Manager。
   * @param readinessListener 接收远端画面可见状态的监听器。
   * @returns 新建的 RemoteVideoController 实例。
   */
  constructor(rtcManager: RtcManaging, readinessListener: (ready: boolean) => void) {
    this.rtcManager = rtcManager;
    this.readinessListener = readinessListener;
    rtcManager.setRemoteVideoRenderedListener((stream: RemoteStream): void => {
      if (this.remoteViewId.length > 0 && this.remoteStream?.key() === stream.key()) {
        this.readinessListener(true);
      }
    });
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
      this.rtcManager.unbindRemoteVideo(previousStream);
    }

    this.readinessListener(false);
    this.remoteStream = stream;
    if (stream === null || this.remoteViewId.length === 0) {
      return;
    }

    this.rtcManager.bindRemoteVideo(
      stream,
      this.remoteViewId,
      this.remoteContentMode
    );
    this.readinessListener(this.rtcManager.hasRenderedRemoteVideo(stream));
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
      this.rtcManager.bindRemoteVideo(stream, viewId, contentMode);
      this.readinessListener(this.rtcManager.hasRenderedRemoteVideo(stream));
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
      this.rtcManager.unbindRemoteVideo(stream);
    }

    this.remoteViewId = '';
    this.readinessListener(false);
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
    this.readinessListener(false);
    this.remoteContentMode = VideoContentMode.FIT;

    if (stream !== null) {
      this.rtcManager.unbindRemoteVideo(stream);
    }
  }
}
