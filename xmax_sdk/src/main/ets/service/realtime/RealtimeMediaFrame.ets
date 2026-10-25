//
//  RealtimeMediaFrame.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { RealtimeVideoFrame } from '../../foundation/media/video/RealtimeVideoFrame';

/** Signed little-endian interleaved PCM16 for remote output or external input. */
export class RealtimeAudioFrame {

  /** The PCM bytes; SDK-delivered output owns a copy valid after callback return. */
  readonly data: Uint8Array;

  /** The number of samples per second in each channel. */
  readonly sampleRate: number;

  /** The number of interleaved audio channels. */
  readonly channels: number;

  /** The number of samples in each channel of this packet. */
  readonly samplesPerChannel: number;

  /** The first sample's media time in microseconds, using the producer clock for external input. */
  readonly timestampUs: number;

  /** The exact packet duration derived from its sample count, in microseconds. */
  get durationUs(): number {
    return this.samplesPerChannel * 1000000 / this.sampleRate;
  }

  /** Creates a PCM packet with an assigned media time. */
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

/**
 * One remote audio or video packet, delivered in arrival order rather than cross-track time order.
 *
 * RTC timestamps retain their provider-defined origins; this API does not establish or certify a
 * shared audio/video rendering clock. Do not independently zero each track when recording.
 * Media buffers remain valid after callback return and must be treated as read-only.
 */
export class RealtimeMediaFrame {

  /** The opaque result binding identity, replaced even when a new binding reuses the same user. */
  readonly streamId: string;

  /** Whether this track starts, changes format or clock, or follows discarded output. */
  readonly isDiscontinuous: boolean;

  /** The copied remote PCM packet or processed video frame. */
  readonly content: RealtimeAudioFrame | RealtimeVideoFrame;

  /** The packet's media time, in microseconds; not a wall-clock or source-file timecode. */
  get timestampUs(): number {
    return this.content.timestampUs;
  }

  /** The audio packet duration, in microseconds; video frame duration is not supplied by RTC. */
  get durationUs(): number | undefined {
    return this.content instanceof RealtimeAudioFrame ? this.content.durationUs : undefined;
  }

  /** Creates a remote output event for one result binding. */
  constructor(
    streamId: string,
    isDiscontinuous: boolean,
    content: RealtimeAudioFrame | RealtimeVideoFrame
  ) {
    this.streamId = streamId;
    this.isDiscontinuous = isDiscontinuous;
    this.content = content;
  }
}

/**
 * Receives serialized remote PCM and video on the ArkTS event loop; move expensive work to a Worker.
 *
 * @param frame One packet, not a synchronized audio/video pair.
 */
export type RealtimeMediaFrameListener = (
  frame: RealtimeMediaFrame
) => void;
