import { EncodingBitratePolicy, VideoBitrateBudget } from './EncodingBitratePolicy';
import { XmaxError, XmaxErrorCode } from '../../foundation/errors/XmaxError';
import { RtcManaging } from '../../foundation/rtc/RtcManaging';
import { VideoEncoderPreference, VideoEncodingConfiguration } from '../../foundation/rtc/VideoEncodingConfiguration';
import { RealtimeVideoEncoderPreference, RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import { EncodingControlling } from './EncodingControlling';

/** 根据最终上传尺寸、帧率和显式编码配置设置 RTC 编码参数。 */
export class EncodingController implements EncodingControlling {
  private readonly rtcManager: RtcManaging;

  constructor(rtcManager: RtcManaging) {
    this.rtcManager = rtcManager;
  }
  configure(videoFormat: RealtimeVideoFormat): void {
    videoFormat.validate();
    const budget: VideoBitrateBudget = EncodingBitratePolicy.resolve(videoFormat);

    let preference: VideoEncoderPreference;
    switch (videoFormat.encoderPreference) {
      case RealtimeVideoEncoderPreference.AUTO:
        preference = VideoEncoderPreference.AUTO;
        break;
      case RealtimeVideoEncoderPreference.MAINTAIN_FRAMERATE:
        preference = VideoEncoderPreference.MAINTAIN_FRAMERATE;
        break;
      case RealtimeVideoEncoderPreference.MAINTAIN_QUALITY:
        preference = VideoEncoderPreference.MAINTAIN_QUALITY;
        break;
      default:
        throw new XmaxError(XmaxErrorCode.INVALID_CONFIGURATION, 'Unsupported video encoder preference');
    }
    this.rtcManager.configureVideoEncoding(new VideoEncodingConfiguration(
      videoFormat.width, videoFormat.height, videoFormat.fps, budget.minimum, budget.maximum, preference
    ));
  }

}
