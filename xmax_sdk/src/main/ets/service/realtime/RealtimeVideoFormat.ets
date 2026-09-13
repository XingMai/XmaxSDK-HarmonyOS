import {
  XmaxError,
  XmaxErrorCode
} from '../../foundation/errors/XmaxError';

/** 上传编码策略：平衡、帧率优先或分辨率优先。 */
export enum RealtimeVideoEncoderPreference {
  AUTO = 'Auto',
  MAINTAIN_FRAMERATE = 'MaintainFramerate',
  MAINTAIN_QUALITY = 'MaintainQuality'
}

/** 实时视频的尺寸、帧率和上传编码配置。 */
export class RealtimeVideoFormat {
  /** 视频宽度，单位为像素，必须为正偶数。 */
  readonly width: number;

  /** 视频高度，单位为像素，必须为正偶数。 */
  readonly height: number;

  /** 视频帧率，单位为 fps，必须为正整数。 */
  readonly fps: number;

  /** 最低上传码率，单位 kbps；undefined 按最终格式计算，0 表示不设最低码率。 */
  readonly minimumBitrate?: number;

  /** 最高上传码率，单位 kbps；undefined 按最终格式计算，指定时必须大于 0。 */
  readonly maximumBitrate?: number;

  /** 上传编码策略偏好，默认为 AUTO，平衡帧率和分辨率。 */
  readonly encoderPreference: RealtimeVideoEncoderPreference;

  constructor(
    width: number,
    height: number,
    fps: number,
    minimumBitrate?: number,
    maximumBitrate?: number,
    encoderPreference: RealtimeVideoEncoderPreference = RealtimeVideoEncoderPreference.AUTO
  ) {
    this.width = width;
    this.height = height;
    this.fps = fps;
    this.minimumBitrate = minimumBitrate;
    this.maximumBitrate = maximumBitrate;
    this.encoderPreference = encoderPreference;
  }

  validate(): void {
    if (!Number.isSafeInteger(this.width) || !Number.isSafeInteger(this.height) ||
      !Number.isSafeInteger(this.fps) || this.width <= 0 || this.height <= 0 || this.fps <= 0 ||
      this.width % 2 !== 0 || this.height % 2 !== 0) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Realtime video width and height must be positive even numbers, and fps must be greater than zero'
      );
    }
    if (this.minimumBitrate !== undefined &&
      (!Number.isSafeInteger(this.minimumBitrate) || this.minimumBitrate < 0)) {
      throw new XmaxError(XmaxErrorCode.INVALID_CONFIGURATION,
        'Minimum bitrate must be a non-negative integer');
    }
    if (this.maximumBitrate !== undefined &&
      (!Number.isSafeInteger(this.maximumBitrate) || this.maximumBitrate <= 0)) {
      throw new XmaxError(XmaxErrorCode.INVALID_CONFIGURATION,
        'Maximum bitrate must be a positive integer');
    }
    if (this.minimumBitrate !== undefined && this.maximumBitrate !== undefined &&
      this.minimumBitrate > this.maximumBitrate) {
      throw new XmaxError(XmaxErrorCode.INVALID_CONFIGURATION,
        'Minimum bitrate must not exceed maximum bitrate');
    }
    switch (this.encoderPreference) {
      case RealtimeVideoEncoderPreference.AUTO:
      case RealtimeVideoEncoderPreference.MAINTAIN_FRAMERATE:
      case RealtimeVideoEncoderPreference.MAINTAIN_QUALITY:
        break;
      default:
        throw new XmaxError(XmaxErrorCode.INVALID_CONFIGURATION, 'Unsupported video encoder preference');
    }
  }

  /** 调整尺寸，保留帧率和上传编码配置。 */
  resized(width: number, height: number): RealtimeVideoFormat {
    return new RealtimeVideoFormat(width, height, this.fps,
      this.minimumBitrate, this.maximumBitrate, this.encoderPreference);
  }
}
