import { RemoteStream } from './RemoteStream';

export interface RtcEventListener {
  /**
   * 处理远端视频发布状态变化。
   *
   * @param userId 远端用户标识。
   * @param published 是否已发布视频。
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
   */
  onSeiMessageReceived(
    stream: RemoteStream,
    message: string
  ): void;
}
