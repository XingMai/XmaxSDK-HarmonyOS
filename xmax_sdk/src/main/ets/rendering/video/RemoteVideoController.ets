//
//  RemoteVideoController.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { RemoteStream } from '../../foundation/rtc/RemoteStream';
import { RtcManaging } from '../../foundation/rtc/RtcManaging';
import { VideoContentMode } from '../../foundation/media/video/VideoContentMode';
import { RemoteVideoControlling } from './RemoteVideoControlling';

/** Manages remote stream bindings to rendering containers. */
export class RemoteVideoController implements RemoteVideoControlling {

  /** The adapter for RTC engine, room, and media services. */
  private readonly rtcManager: RtcManaging;

  /**
   * Reports whether remote video is ready to display.
   *
   * @param ready Whether video is visible.
   */
  private readonly readinessListener: (
    ready: boolean
  ) => void;

  /** The current remote result stream. */
  private remoteStream: RemoteStream | null = null;

  /** The view currently bound to remote rendering. */
  private remoteViewId: string = '';

  /** The content mode for remote rendering. */
  private remoteContentMode: VideoContentMode = VideoContentMode.FIT;

  /**
   * Cache real display events only within the current result binding, not the RTC publication's
   * history.
   */
  private currentGenerationRendered: boolean = false;

  /**
   * Creates a remote video controller.
   *
   * @param rtcManager The RTC manager binding remote video.
   * @param readinessListener The remote video visibility handler.
   */
  constructor(
    rtcManager: RtcManaging,
    readinessListener: (
      ready: boolean
    ) => void
  ) {
    this.rtcManager = rtcManager;
    this.readinessListener = readinessListener;

    rtcManager.setRemoteVideoRenderedListener((stream: RemoteStream): void => {
      if (this.remoteViewId.length > 0 && this.remoteStream?.key() === stream.key()) {
        this.currentGenerationRendered = true;
        this.readinessListener(true);
      }
    });
  }

  /**
   * Updates the remote stream to render.
   *
   * @param stream The remote stream, or null to clear it.
   */
  setRemoteStream(
    stream: RemoteStream | null
  ): void {
    const previousStream: RemoteStream | null = this.remoteStream;
    if (previousStream !== null && previousStream !== stream) {
      this.rtcManager.unbindRemoteVideo(previousStream);
    }

    this.currentGenerationRendered = false;
    this.readinessListener(false);
    this.remoteStream = stream;
    if (stream === null || this.remoteViewId.length === 0) {
      return;
    }

    this.bindCurrentVideo();
  }

  /**
   * Resubscribes when a new task reuses a rendered RTC stream so the renderer reports a fresh first
   * frame. Canvas rebinding alone does not guarantee a first-frame event; preserve the connection
   * and local stream.
   */
  private bindCurrentVideo(): void {
    const stream: RemoteStream | null = this.remoteStream;
    if (stream === null || this.remoteViewId.length === 0) {
      return;
    }

    const renewSubscription: boolean = !this.currentGenerationRendered &&
      this.rtcManager.hasRenderedRemoteVideo(stream);
    if (renewSubscription) {
      this.rtcManager.subscribeRemoteVideo(
        stream.userId,
        false
      );
    }
    this.rtcManager.bindRemoteVideo(
      stream,
      this.remoteViewId,
      this.remoteContentMode
    );
    if (renewSubscription) {
      this.rtcManager.subscribeRemoteVideo(
        stream.userId,
        true
      );
    }

    this.readinessListener(this.currentGenerationRendered);
  }

  /**
   * Binds remote video to a rendering container.
   *
   * @param viewId The rendering container identifier.
   * @param contentMode The video display mode.
   */
  attach(
    viewId: string,
    contentMode: VideoContentMode
  ): void {
    this.remoteViewId = viewId;
    this.remoteContentMode = contentMode;

    const stream: RemoteStream | null = this.remoteStream;
    if (stream !== null) {
      this.bindCurrentVideo();
    }
  }

  /**
   * Detaches a rendering container from remote video.
   *
   * @param viewId The rendering container identifier.
   */
  detach(
    viewId: string
  ): void {
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

  /** Clears the remote stream and rendering bindings. */
  reset(): void {
    const stream: RemoteStream | null = this.remoteStream;
    this.remoteStream = null;
    this.remoteViewId = '';
    this.currentGenerationRendered = false;
    this.readinessListener(false);
    this.remoteContentMode = VideoContentMode.FIT;

    if (stream !== null) {
      this.rtcManager.unbindRemoteVideo(stream);
    }
  }
}
