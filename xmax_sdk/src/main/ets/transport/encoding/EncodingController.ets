import { RtcProviding } from '../../foundation/rtc/RtcProviding';
import { VideoEncodingConfiguration } from '../../foundation/rtc/VideoEncodingConfiguration';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import { EncodingControlling } from './EncodingControlling';

/** 根据实时生成视频格式配置 RTC 视频编码参数。 */
export class EncodingController implements EncodingControlling {

  // 基础层组件
  private readonly rtcProvider: RtcProviding;

  /**
   * 创建视频编码 Controller。
   *
   * @param rtcProvider 提供视频编码配置能力的 RTC Provider。
   */
  constructor(rtcProvider: RtcProviding) {
    this.rtcProvider = rtcProvider;
  }

  /**
   * 校验并应用视频编码格式。
   *
   * @param videoFormat 实时生成使用的视频格式。
   * @returns 无返回值。
   */
  configure(videoFormat: RealtimeVideoFormat): void {
    videoFormat.validate();

    this.rtcProvider.configureVideoEncoding(new VideoEncodingConfiguration(
      videoFormat.width,
      videoFormat.height,
      videoFormat.fps
    ));
  }
}
