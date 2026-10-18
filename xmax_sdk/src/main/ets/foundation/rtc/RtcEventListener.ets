//
//  RtcEventListener.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { RemoteStream } from './RemoteStream';

/** 接收远端音视频发布状态及 SEI 消息，供实时业务识别生成结果流。 */
export interface RtcEventListener {
  /**
   * 处理远端音频发布状态变化。
   *
   * @param userId 远端用户标识。
   * @param published 是否已发布音频。
   * @returns 无返回值。
   */
  onRemoteAudioPublished(
    userId: string,
    published: boolean
  ): void;

  /**
   * 处理远端视频发布状态变化。
   *
   * @param userId 远端用户标识。
   * @param published 是否已发布视频。
   * @returns 无返回值。
   */
  onRemoteVideoPublished(
    userId: string,
    published: boolean
  ): void;

  /**
   * 处理远端流携带的 SEI 消息。
   *
   * @param stream 远端流信息。
   * @param message SEI 消息内容。
   * @returns 无返回值。
   */
  onSeiMessageReceived(
    stream: RemoteStream,
    message: string
  ): void;
}
