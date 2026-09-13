export enum VideoEncoderPreference {
  AUTO,
  MAINTAIN_FRAMERATE,
  MAINTAIN_QUALITY
}

export class VideoEncodingConfiguration {
  readonly width: number;
  readonly height: number;
  readonly frameRate: number;
  readonly minimumBitrate: number;
  readonly maximumBitrate: number;
  readonly encoderPreference: VideoEncoderPreference;

  constructor(
    width: number,
    height: number,
    frameRate: number,
    minimumBitrate: number = 0,
    maximumBitrate: number = -1,
    encoderPreference: VideoEncoderPreference = VideoEncoderPreference.AUTO
  ) {
    this.width = width;
    this.height = height;
    this.frameRate = frameRate;
    this.minimumBitrate = minimumBitrate;
    this.maximumBitrate = maximumBitrate;
    this.encoderPreference = encoderPreference;
  }
}
