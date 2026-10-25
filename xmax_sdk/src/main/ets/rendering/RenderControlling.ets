//
//  RenderControlling.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { ImageSize } from '../service/media/ImageSize';
import { RealtimeVideoFrameListener } from '../service/realtime/RealtimeVideoFrame';
import { RemoteStream } from '../foundation/rtc/RemoteStream';
import { XmaxError } from '../foundation/errors/XmaxError';
import { InteractionControlling } from '../media/interaction/InteractionControlling';
import { RealtimeVideoTrack } from '../service/realtime/RealtimeVideoTrack';

/** The rendering layer interface used by Core. */
export interface RenderControlling {

  /**
   * Sets remote frame delivery; null removes the listener and clears pending frames.
   *
   * @param listener The event handler, or null to remove it.
   */
  setRemoteVideoFrameListener(
    listener: RealtimeVideoFrameListener | null
  ): void;

  /** Stops public frame delivery until a new remote stream is set. */
  stopRemoteVideoFrameDelivery(): void;

  /** Captures the next remote frame as a frozen result overlay. */
  freezeRemoteVideo(): Promise<void>;

  /** Removes the frozen overlay after the next remote frame arrives. */
  resumeRemoteVideo(): Promise<void>;

  /**
   * Updates the remote RTC stream to render.
   *
   * @param stream The remote stream, or null to clear it.
   */
  setRemoteStream(
    stream: RemoteStream | null
  ): void;

  /** Waits for a usable frame after the current SEI match, rejecting on timeout or stream removal. */
  waitUntilRemoteFrameReady(): Promise<void>;

  /**
   * Ends a startup frame wait immediately on a fatal asynchronous error.
   *
   * @param error The fatal failure rejecting the pending first-frame wait.
   */
  failRemoteFrameWait(
    error: XmaxError
  ): void;

  /**
   * Registers rendering and interaction bindings for a remote track.
   *
   * @param track The remote track to register.
   * @param interactionController The media component receiving trajectory interactions.
   * @param resolvedMediaSize The processed local media dimensions defining interaction coordinates
   * independently of return resolution.
   */
  registerRemoteTrack(
    track: RealtimeVideoTrack,
    interactionController: InteractionControlling,
    resolvedMediaSize: ImageSize
  ): void;

  /**
   * Unregisters remote track bindings and resets remote video.
   *
   * @param track The track to unregister; an absent track only resets video.
   */
  resetRemoteTrack(
    track: RealtimeVideoTrack | null
  ): void;
}
