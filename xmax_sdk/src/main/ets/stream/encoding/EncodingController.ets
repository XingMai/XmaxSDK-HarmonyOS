import { XmaxError, XmaxErrorCode } from '../../foundation/errors/XmaxError';
import { RtcManaging } from '../../foundation/rtc/RtcManaging';
import { VideoEncoderPreference, VideoEncodingConfiguration } from '../../foundation/rtc/VideoEncodingConfiguration';
import { RealtimeVideoEncoderPreference, RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import { EncodingControlling } from './EncodingControlling';

class BitratePoint {
  readonly value: number;
  readonly bitrate: number;

  constructor(value: number, bitrate: number) {
    this.value = value;
    this.bitrate = bitrate;
  }
}

/** 根据最终上传尺寸、帧率和显式编码配置设置 RTC 编码参数。 */
export class EncodingController implements EncodingControlling {
  private readonly rtcManager: RtcManaging;

  constructor(rtcManager: RtcManaging) {
    this.rtcManager = rtcManager;
  }
  configure(videoFormat: RealtimeVideoFormat): void {
    videoFormat.validate();
    let minimum: number;
    let maximum: number;
    if (videoFormat.minimumBitrate !== undefined && videoFormat.maximumBitrate !== undefined) {
      minimum = videoFormat.minimumBitrate;
      maximum = videoFormat.maximumBitrate;
    } else {
      const bitrates: number[] = EncodingController.resolveBitrates(
        videoFormat.width * videoFormat.height, videoFormat.fps
      );
      const defaultMinimum: number = Math.max(1, Math.round(bitrates[0]));
      const defaultMaximum: number = Math.max(defaultMinimum + 1, Math.round(bitrates[1]));
      if (!Number.isSafeInteger(defaultMaximum)) {
        throw new XmaxError(XmaxErrorCode.INVALID_CONFIGURATION,
          'Realtime video format exceeds the supported bitrate range');
      }
      minimum = videoFormat.minimumBitrate ?? defaultMinimum;
      maximum = videoFormat.maximumBitrate ?? defaultMaximum;
    }
    if (minimum > maximum) {
      throw new XmaxError(XmaxErrorCode.INVALID_CONFIGURATION,
        'Minimum bitrate must not exceed maximum bitrate after applying SDK defaults');
    }

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
      videoFormat.width, videoFormat.height, videoFormat.fps, minimum, maximum, preference
    ));
  }

  // 与 iOS 使用相同参考表：按像素面积和帧率插值，表外按最近端点比例外推。
  // 流畅优先推荐值作为最低码率，画质优先推荐值作为最高码率，单位 kbps。
  // https://docs.byteplus.com/id/docs/byteplus-rtc/docs-70122
  private static readonly REFERENCE_15_FPS: BitratePoint[] = [
    new BitratePoint(120 * 120, 50),
    new BitratePoint(160 * 120, 65),
    new BitratePoint(180 * 180, 100),
    new BitratePoint(240 * 180, 120),
    new BitratePoint(320 * 180, 140),
    new BitratePoint(320 * 240, 200),
    new BitratePoint(424 * 240, 220),
    new BitratePoint(360 * 360, 260),
    new BitratePoint(480 * 360, 320),
    new BitratePoint(640 * 360, 400),
    new BitratePoint(640 * 480, 500),
    new BitratePoint(848 * 480, 610),
    new BitratePoint(960 * 720, 910),
    new BitratePoint(1280 * 720, 1130),
    new BitratePoint(1920 * 1080, 2080)
  ];
  private static readonly REFERENCE_30_FPS: BitratePoint[] = [
    new BitratePoint(360 * 360, 400),
    new BitratePoint(480 * 360, 490),
    new BitratePoint(640 * 360, 600),
    new BitratePoint(640 * 480, 750),
    new BitratePoint(848 * 480, 930),
    new BitratePoint(960 * 720, 1380),
    new BitratePoint(1280 * 720, 1710),
    new BitratePoint(1920 * 1080, 3150)
  ];

  private static resolveBitrates(pixels: number, fps: number): number[] {
    const bitrate15: number = EncodingController.interpolate(pixels, EncodingController.REFERENCE_15_FPS);
    const first30: BitratePoint = EncodingController.REFERENCE_30_FPS[0];
    const bitrate30: number = pixels < first30.value ?
      bitrate15 * (first30.bitrate / EncodingController.interpolate(first30.value, EncodingController.REFERENCE_15_FPS)) :
      EncodingController.interpolate(pixels, EncodingController.REFERENCE_30_FPS);
    const bitrate10: number = bitrate15 * (400 / 500);
    return [
      EncodingController.interpolate(fps, [
        new BitratePoint(10, bitrate10), new BitratePoint(15, bitrate15),
        new BitratePoint(30, bitrate30), new BitratePoint(60, bitrate30 * (4780 / 3150))
      ]),
      EncodingController.interpolate(fps, [
        new BitratePoint(10, bitrate10 * 2), new BitratePoint(15, bitrate15 * 2),
        new BitratePoint(30, bitrate30 * 2), new BitratePoint(60, bitrate30 * (6500 / 3150))
      ])
    ];
  }

  private static interpolate(value: number, points: BitratePoint[]): number {
    const first: BitratePoint = points[0];
    if (value <= first.value) {
      return first.bitrate * (value / first.value);
    }
    for (let index: number = 1; index < points.length; index++) {
      const upper: BitratePoint = points[index];
      if (value <= upper.value) {
        const lower: BitratePoint = points[index - 1];
        const ratio: number = (value - lower.value) / (upper.value - lower.value);
        return lower.bitrate + (upper.bitrate - lower.bitrate) * ratio;
      }
    }
    const last: BitratePoint = points[points.length - 1];
    return last.bitrate * (value / last.value);
  }
}
