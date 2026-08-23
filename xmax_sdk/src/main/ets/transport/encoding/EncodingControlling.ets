import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';

/** 定义视频编码参数的配置能力。 */
export interface EncodingControlling {

  /**
   * 配置视频编码参数。
   *
   * @param videoFormat 视频编码格式。
   * @returns 无返回值。
   */
  configure(
    videoFormat: RealtimeVideoFormat
  ): void;
}
