//
//  RtcEventListener.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { RemoteStream } from './RemoteStream';

/** Receives remote publication and SEI events for generation result matching. */
export interface RtcEventListener {

  /** Receives server text signaling, including directed messages, for the current room. */
  onRoomSignalReceived?(
    userId: string,
    message: string
  ): void;

  /**
   * Handles remote audio publication changes.
   *
   * @param userId The remote user identifier.
   * @param published Whether audio is published.
   */
  onRemoteAudioPublished(
    userId: string,
    published: boolean
  ): void;

  /**
   * Handles remote video publication changes.
   *
   * @param userId The remote user identifier.
   * @param published Whether video is published.
   */
  onRemoteVideoPublished(
    userId: string,
    published: boolean
  ): void;

  /**
   * Handles SEI messages associated with a remote stream.
   *
   * @param stream The remote stream information.
   * @param message The SEI message content.
   */
  onSeiMessageReceived(
    stream: RemoteStream,
    message: string
  ): void;
}
