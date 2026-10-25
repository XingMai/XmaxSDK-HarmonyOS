//
//  RtcAudioConverter.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { AudioFrameType, IAudioFrame } from '@bytertc/volcenginertc';
import { XmaxError, XmaxErrorCode } from '../errors/XmaxError';
import { RtcRemoteAudioFrame } from './RtcRemoteAudioFrame';

/** Copies validated PCM before RTC callback storage can be reused. */
export class RtcAudioConverter {

  /**
   * Copies the declared PCM range without changing its format or native timestamp.
   *
   * @param frame The native PCM16 packet, valid only during the RTC callback.
   *
   * @throws An RTC error if PCM metadata, byte bounds, or the timestamp is invalid.
   */
  static copyRemoteFrame(
    frame: IAudioFrame
  ): RtcRemoteAudioFrame {
    const sampleRate: number = frame.sample_rate;
    const channels: number = frame.channel;
    const byteCount: number = frame.data_size;
    const samplesPerChannel: number = byteCount / (channels * 2);
    const storage: Uint8Array | ArrayBuffer = frame.data;
    const input: Uint8Array | undefined = storage instanceof Uint8Array ? storage :
      storage instanceof ArrayBuffer ? new Uint8Array(storage) : undefined;

    if (frame.frame_type !== AudioFrameType.kFrameTypePCM16 ||
      !Number.isSafeInteger(frame.timestamp_us) || frame.timestamp_us < 0 ||
      !Number.isInteger(sampleRate) || sampleRate < 8000 || sampleRate > 192000 ||
      (channels !== 1 && channels !== 2) || !Number.isSafeInteger(byteCount) ||
      input === undefined || byteCount > input.byteLength ||
      !Number.isInteger(samplesPerChannel) || samplesPerChannel < 1 || samplesPerChannel > 192000) {
      throw new XmaxError(
        XmaxErrorCode.RTC_ERROR,
        `Invalid remote PCM16 audio frame: type=${frame.frame_type}, rate=${sampleRate}, ` +
        `channels=${channels}, bytes=${byteCount}, available=${input?.byteLength}, timestampUs=${frame.timestamp_us}`
      );
    }

    const data: Uint8Array = new Uint8Array(byteCount);
    data.set(input.subarray(0, byteCount));
    return new RtcRemoteAudioFrame(
      data,
      sampleRate,
      channels,
      samplesPerChannel,
      frame.timestamp_us
    );
  }
}
