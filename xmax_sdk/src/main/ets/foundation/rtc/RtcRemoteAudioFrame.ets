//
//  RtcRemoteAudioFrame.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/** A copied remote PCM packet retaining the RTC provider's native audio time. */
export class RtcRemoteAudioFrame {

  /** The owned, interleaved PCM16 bytes. */
  readonly data: Uint8Array;

  /** The actual per-channel sample rate, in Hz. */
  readonly sampleRate: number;

  /** The interleaved channel count. */
  readonly channels: number;

  /** The number of samples per channel. */
  readonly samplesPerChannel: number;

  /** The provider-defined audio timestamp, in microseconds. */
  readonly timestampUs: number;

  /** Creates an owned remote PCM packet. */
  constructor(
    data: Uint8Array,
    sampleRate: number,
    channels: number,
    samplesPerChannel: number,
    timestampUs: number
  ) {
    this.data = data;
    this.sampleRate = sampleRate;
    this.channels = channels;
    this.samplesPerChannel = samplesPerChannel;
    this.timestampUs = timestampUs;
  }
}
