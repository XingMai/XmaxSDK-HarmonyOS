//
//  RemoteVideoControlling.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { RemoteStream } from '../../foundation/rtc/RemoteStream';
import { VideoContentMode } from '../../foundation/media/video/VideoContentMode';

/** An interface for remote video rendering bindings. */
export interface RemoteVideoControlling {

  /**
   * Sets the current remote video stream.
   *
   * @param stream The remote stream, or null to clear it.
   */
  setRemoteStream(
    stream: RemoteStream | null
  ): void;

  /**
   * Binds remote video to a rendering container.
   *
   * @param viewId The rendering container identifier.
   * @param contentMode The video display mode.
   */
  attach(
    viewId: string,
    contentMode: VideoContentMode
  ): void;

  /**
   * Detaches remote video from its rendering container.
   *
   * @param viewId The rendering container identifier.
   */
  detach(
    viewId: string
  ): void;

  /** Clears the remote stream and rendering bindings. */
  reset(): void;
}
