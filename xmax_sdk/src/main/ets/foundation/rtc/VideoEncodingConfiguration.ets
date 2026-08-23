export class VideoEncodingConfiguration {
  readonly width: number;
  readonly height: number;
  readonly frameRate: number;
  readonly minimumBitrate: number;
  readonly maximumBitrate: number;

  constructor(
    width: number,
    height: number,
    frameRate: number,
    minimumBitrate: number = 0,
    maximumBitrate: number = -1
  ) {
    this.width = width;
    this.height = height;
    this.frameRate = frameRate;
    this.minimumBitrate = minimumBitrate;
    this.maximumBitrate = maximumBitrate;
  }
}
