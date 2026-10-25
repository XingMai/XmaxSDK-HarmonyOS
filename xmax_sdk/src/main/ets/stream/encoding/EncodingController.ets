//
//  EncodingController.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { EncodingBitratePolicy, VideoBitrateBudget } from './EncodingBitratePolicy';
import { XmaxError, XmaxErrorCode } from '../../foundation/errors/XmaxError';
import { RtcManaging } from '../../foundation/rtc/RtcManaging';
import { VideoEncoderPreference, VideoEncodingConfiguration } from '../../foundation/rtc/VideoEncodingConfiguration';
import { RealtimeVideoEncoderPreference, RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import { EncodingControlling } from './EncodingControlling';

/** Configures RTC encoding from final uplink dimensions, rate, and explicit settings. */
export class EncodingController implements EncodingControlling {

  /** The adapter for RTC engine, room, and media services. */
  private readonly rtcManager: RtcManaging;

  /** Creates an encoding controller. */
  constructor(
    rtcManager: RtcManaging
  ) {
    this.rtcManager = rtcManager;
  }

  /**
   * Resolves a bitrate budget and submits RTC encoding configuration.
   *
   * @param videoFormat The video encoding format.
   */
  configure(
    videoFormat: RealtimeVideoFormat
  ): void {
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
        throw new XmaxError(
          XmaxErrorCode.INVALID_CONFIGURATION,
          'Unsupported video encoder preference'
        );
    }
    this.rtcManager.configureVideoEncoding(new VideoEncodingConfiguration(
      videoFormat.width,
      videoFormat.height,
      videoFormat.fps,
      budget.minimum,
      budget.maximum,
      preference
    ));
  }

}
