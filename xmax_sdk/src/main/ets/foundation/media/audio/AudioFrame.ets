/** RTC 外部音频链路使用的单声道 PCM 音频帧。 */
export class AudioFrame {
  static readonly SAMPLE_RATE: number = 48000;
  static readonly CHANNEL_COUNT: number = 1;
  static readonly SAMPLES_PER_FRAME: number = 480;

  readonly data: Uint8Array;
  readonly timestampUs: number;

  constructor(
    data: Uint8Array,
    timestampUs: number
  ) {
    this.data = data;
    this.timestampUs = timestampUs;
  }
}
