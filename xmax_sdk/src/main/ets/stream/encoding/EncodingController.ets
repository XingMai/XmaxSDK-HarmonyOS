//
//  EncodingController.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { EncodingBitratePolicy, VideoBitrateBudget } from './EncodingBitratePolicy';
import { XmaxError, XmaxErrorCode } from '../../foundation/errors/XmaxError';
import { RtcManaging } from '../../foundation/rtc/RtcManaging';
import { VideoEncoderPreference, VideoEncodingConfiguration } from '../../foundation/rtc/VideoEncodingConfiguration';
import { RealtimeVideoEncoderPreference, RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import { EncodingControlling } from './EncodingControlling';

/** 根据最终上传尺寸、帧率和显式编码配置设置 RTC 编码参数。 */
export class EncodingController implements EncodingControlling {

  /** RTC 编码配置提交 */
  private readonly rtcManager: RtcManaging;

  /**
   * 创建视频编码控制器。
   *
   * @param rtcManager 提供音视频采集、发布和订阅能力的 RTC 组件。
   * @returns 新建的 EncodingController 实例。
   */
  constructor(rtcManager: RtcManaging) {
    this.rtcManager = rtcManager;
  }

  /**
   * 按视频格式计算码率预算并提交 RTC 编码配置。
   *
   * @param videoFormat 视频编码格式。
   * @returns 无返回值。
   */
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
