//
//  ExternalAudioFrameConverter.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { XmaxError, XmaxErrorCode } from '../../foundation/errors/XmaxError';
import { AudioFrame } from '../../foundation/media/audio/AudioFrame';
import { RealtimeAudioFrame } from '../../service/realtime/RealtimeMediaFrame';

/** Converts a serialized external PCM16 stream to timestamped 48 kHz mono packets. */
export class ExternalAudioFrameConverter {

  // Binding format and segment clock

  /** The fixed source sample rate, established by the first valid packet. */
  private sampleRate: number = 0;

  /** The fixed source channel count. */
  private channels: number = 0;

  /** The expected timestamp of the next input buffer. */
  private nextInputUs: number | undefined;

  /** The first sample timestamp in the current continuous segment. */
  private anchorUs: number = 0;

  // Continuous resampling and packetization

  /** The index of the current source sample, shared across input buffers. */
  private sourceIndex: number = 0;

  /** The fractional source position of the next output sample. */
  private nextOutputPosition: number = 0;

  /** The preceding source mono sample used for linear interpolation. */
  private previousSample: number = 0;

  /** The converted sample count within this segment. */
  private outputSamples: number = 0;

  /** The incomplete output packet, never shared with the receiver. */
  private packet: Int16Array = new Int16Array(AudioFrame.SAMPLES_PER_FRAME);

  /** The valid sample count of the incomplete packet. */
  private packetSamples: number = 0;

  /**
   * Converts ready PCM synchronously, retaining less than one output packet.
   *
   * @param frame PCM on the source's shared monotonic media timeline.
   * @param handler The receiver for owned 10 ms packets.
   */
  append(
    frame: RealtimeAudioFrame,
    handler: (
      frame: AudioFrame
    ) => void
  ): void {
    if (!Number.isFinite(frame.timestampUs) || frame.timestampUs < 0) {
      return;
    }

    const rate: number = frame.sampleRate;
    const channels: number = frame.channels;
    if (!Number.isSafeInteger(rate) || rate < 8000 || rate > 192000 ||
      !Number.isSafeInteger(channels) || channels < 1 || channels > 8 ||
      !Number.isSafeInteger(frame.samplesPerChannel) || frame.samplesPerChannel <= 0 ||
      frame.data.byteLength !== frame.samplesPerChannel * channels * 2 ||
      frame.data.byteLength > 4 * 1024 * 1024) {
      throw new XmaxError(
        XmaxErrorCode.MEDIA_ERROR,
        'External audio requires ready interleaved PCM16 samples'
      );
    }
    if (this.sampleRate !== 0 && (this.sampleRate !== rate || this.channels !== channels)) {
      throw new XmaxError(
        XmaxErrorCode.MEDIA_ERROR,
        'External PCM format cannot change during a binding'
      );
    }

    const difference: number = this.nextInputUs === undefined ? 0 : frame.timestampUs - this.nextInputUs;
    const tolerance: number = 500000 / rate;
    if (difference < -tolerance) {
      return;
    }
    if (this.sampleRate === 0 || difference > tolerance) {
      this.anchorUs = frame.timestampUs;
      this.sourceIndex = 0;
      this.nextOutputPosition = 0;
      this.previousSample = 0;
      this.outputSamples = 0;
      this.packetSamples = 0;
      this.packet = new Int16Array(AudioFrame.SAMPLES_PER_FRAME);
    }
    this.sampleRate = rate;
    this.channels = channels;

    const input = new DataView(
      frame.data.buffer,
      frame.data.byteOffset,
      frame.data.byteLength
    );
    const step: number = rate / AudioFrame.SAMPLE_RATE;
    for (let index: number = 0; index < frame.samplesPerChannel; index++) {
      let sum: number = 0;
      for (let channel: number = 0; channel < channels; channel++) {
        sum += input.getInt16(
          (index * channels + channel) * 2,
          true
        );
      }
      const current: number = sum / channels;
      if (this.sourceIndex === 0) {
        this.previousSample = current;
      }

      while (this.nextOutputPosition <= this.sourceIndex) {
        const previousPosition: number = Math.max(0, this.sourceIndex - 1);
        const fraction: number = this.sourceIndex === 0 ? 0 : this.nextOutputPosition - previousPosition;
        this.packet[this.packetSamples++] = Math.round(this.previousSample +
          (current - this.previousSample) * fraction);
        this.nextOutputPosition += step;
        this.outputSamples++;

        if (this.packetSamples === AudioFrame.SAMPLES_PER_FRAME) {
          const data = new Uint8Array(this.packet.buffer);
          const timestampUs: number = this.anchorUs +
            (this.outputSamples - AudioFrame.SAMPLES_PER_FRAME) * 1000000 / AudioFrame.SAMPLE_RATE;
          this.packet = new Int16Array(AudioFrame.SAMPLES_PER_FRAME);
          this.packetSamples = 0;
          handler(new AudioFrame(
            data,
            timestampUs
          ));
        }
      }

      this.previousSample = current;
      this.sourceIndex++;
    }
    this.nextInputUs = frame.timestampUs + frame.samplesPerChannel * 1000000 / rate;
  }
}
