import { VideoFrame } from '../../foundation/media/video/VideoFrame';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import { RealtimeVideoTrack } from '../../service/realtime/RealtimeVideoTrack';

export type PreviewRelease = () => void;

/** 定义本地视频首帧缓存和冻结预览能力。 */
export interface LocalVideoPreviewControlling {

  /**
   * 设置本地视频预览的目标格式。
   *
   * @param videoFormat 本地视频发送使用的视频格式。
   * @returns 无返回值。
   */
  configure(
    videoFormat: RealtimeVideoFormat
  ): void;

  /**
   * 缓存本地视频的第一帧。
   *
   * @param frame 本地视频输出的视频帧。
   * @returns 无返回值。
   */
  captureFirstFrame(
    frame: VideoFrame
  ): void;

  /**
   * 使用第一帧冻结本地视频预览。
   *
   * @param track 需要冻结预览的视频轨道。
   * @returns 解除本次预览冻结的方法。
   */
  freeze(
    track: RealtimeVideoTrack
  ): PreviewRelease;

  /**
   * 清理本地视频预览资源。
   *
   * @returns 清理完成后的 Promise。
   */
  reset(): Promise<void>;
}
