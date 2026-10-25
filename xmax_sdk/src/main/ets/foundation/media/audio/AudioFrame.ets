//
//  AudioFrame.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/** A mono PCM frame for external RTC audio input. */
export class AudioFrame {

  /** The PCM output sample rate, in Hz. */
  static readonly SAMPLE_RATE: number = 48000;

  /** The mono PCM channel count. */
  static readonly CHANNEL_COUNT: number = 1;

  /** The samples per channel in each 10 ms PCM frame. */
  static readonly SAMPLES_PER_FRAME: number = 480;

  /** The mono PCM frame bytes. */
  readonly data: Uint8Array;

  /** The frame timestamp, in microseconds. */
  readonly timestampUs: number;

  /** Creates a 48 kHz mono PCM audio frame. */
  constructor(
    data: Uint8Array,
    timestampUs: number
  ) {
    this.data = data;
    this.timestampUs = timestampUs;
  }
}
