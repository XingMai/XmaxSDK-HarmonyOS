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
    if (frame.frame_type !== AudioFrameType.kFrameTypePCM16 ||
      !Number.isSafeInteger(frame.timestamp_us) || frame.timestamp_us < 0 ||
      !Number.isInteger(sampleRate) || sampleRate < 8000 || sampleRate > 192000 ||
      (channels !== 1 && channels !== 2) || !Number.isSafeInteger(byteCount) ||
      !(frame.data instanceof Uint8Array) || byteCount > frame.data.byteLength ||
      !Number.isInteger(samplesPerChannel) || samplesPerChannel < 1 || samplesPerChannel > 192000) {
      throw new XmaxError(
        XmaxErrorCode.RTC_ERROR,
        'Invalid remote PCM16 audio frame'
      );
    }

    const data: Uint8Array = new Uint8Array(byteCount);
    data.set(frame.data.subarray(0, byteCount));
    return new RtcRemoteAudioFrame(
      data,
      sampleRate,
      channels,
      samplesPerChannel,
      frame.timestamp_us
    );
  }
}
