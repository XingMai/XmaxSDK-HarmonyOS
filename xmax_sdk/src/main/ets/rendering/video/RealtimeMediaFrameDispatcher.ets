//
//  RealtimeMediaFrameDispatcher.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { util } from '@kit.ArkTS';
import { RtcRemoteAudioFrame } from '../../foundation/rtc/RtcRemoteAudioFrame';
import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import { RealtimeAudioFrame, RealtimeMediaFrame, RealtimeMediaFrameListener } from '../../service/realtime/RealtimeMediaFrame';
import { RealtimeVideoFrame } from '../../foundation/media/video/RealtimeVideoFrame';
import { RemoteAudioTimeline, ResolvedRemoteAudioFrame } from './RemoteAudioTimeline';

/** Delivers bounded remote media in arrival order on the ArkTS event loop. */
export class RealtimeMediaFrameDispatcher {

  /** The currently registered application receiver. */
  private listener: RealtimeMediaFrameListener | null = null;

  /** The identity shared by packets from one result binding. */
  private bindingId: string | undefined;

  /** The revision rejecting obsolete timers and callback batches. */
  private version: number = 0;

  /** The queued packets in provider callback order. */
  private pendingFrames: RealtimeMediaFrame[] = [];

  /** The retained packet count, including a callback currently running. */
  private pendingCount: number = 0;

  /** The retained media bytes, including a callback currently running. */
  private pendingBytes: number = 0;

  /** The scheduled delivery timer, or -1 when no delivery is scheduled. */
  private timer: number = -1;

  /** Whether a callback batch is running and may enqueue follow-up output. */
  private delivering: boolean = false;

  /** The sample-based audio timeline for the current receiver and binding. */
  private readonly audioTimeline: RemoteAudioTimeline = new RemoteAudioTimeline();

  /** Whether the next admitted audio packet must mark a discontinuity. */
  private audioDiscontinuous: boolean = true;

  /** Whether the next admitted video frame must mark a discontinuity. */
  private videoDiscontinuous: boolean = true;

  /** The previously observed video timestamp, in microseconds. */
  private lastVideoTimestampUs: number | undefined;

  /** The previous dimensions, format, and rotation used to detect video format changes. */
  private lastVideoFormat: string = '';

  /** The maximum retained packets across the queue and an active callback. */
  private readonly maximumPendingFrames: number;

  /** The maximum retained media bytes across the queue and an active callback. */
  private readonly maximumPendingBytes: number;

  /** Creates a queue bounded by packet count and byte size. */
  constructor(
    maximumPendingFrames: number = 256,
    maximumPendingBytes: number = 32 * 1024 * 1024
  ) {
    this.maximumPendingFrames = maximumPendingFrames;
    this.maximumPendingBytes = maximumPendingBytes;
  }

  /** Whether an application requests unified media output. */
  get hasListener(): boolean {
    return this.listener !== null;
  }

  /** The current result binding identity, absent when media delivery is stopped. */
  get streamId(): string | undefined {
    return this.bindingId;
  }

  /** Replaces the receiver, invalidating queued packets and resetting track continuity. */
  setListener(
    listener: RealtimeMediaFrameListener | null
  ): void {
    this.invalidate();
    this.listener = listener;
  }

  /** Starts or clears a binding, rejecting output captured for previous bindings. */
  setStream(
    active: boolean
  ): void {
    this.invalidate();
    this.bindingId = active ? util.generateRandomUUID() : undefined;
  }

  /**
   * Enqueues owned PCM while preserving native origin and advancing continuous sample time.
   *
   * @param frame The validated PCM packet copied during the native callback.
   * @param streamId The producer's result binding identity.
   */
  dispatchAudio(
    frame: RtcRemoteAudioFrame,
    streamId: string
  ): void {
    if (this.bindingId !== streamId || this.listener === null) {
      return;
    }

    const resolved: ResolvedRemoteAudioFrame = this.audioTimeline.resolve(frame);
    const output: RealtimeMediaFrame = new RealtimeMediaFrame(
      streamId,
      this.audioDiscontinuous || resolved.isDiscontinuous,
      resolved.frame
    );
    this.audioDiscontinuous = !this.enqueue(output);
  }

  /**
   * Enqueues processed video without shifting its native timestamp.
   *
   * @param frame The owned remote video frame.
   * @param streamId The producer's result binding identity.
   */
  dispatchVideo(
    frame: RealtimeVideoFrame,
    streamId: string
  ): void {
    if (this.bindingId !== streamId || this.listener === null) {
      return;
    }
    if (!Number.isSafeInteger(frame.timestampUs) || frame.timestampUs < 0) {
      this.videoDiscontinuous = true;
      return;
    }

    const format: string = `${frame.width}:${frame.height}:${frame.pixelFormat}:${frame.rotation}`;
    const backwards: boolean = this.lastVideoTimestampUs !== undefined &&
      frame.timestampUs <= this.lastVideoTimestampUs;
    const changed: boolean = this.lastVideoFormat.length > 0 && this.lastVideoFormat !== format;
    this.lastVideoTimestampUs = frame.timestampUs;
    this.lastVideoFormat = format;

    const output: RealtimeMediaFrame = new RealtimeMediaFrame(
      streamId,
      this.videoDiscontinuous || backwards || changed,
      frame
    );
    this.videoDiscontinuous = !this.enqueue(output);
  }

  /** Clears queued packets and continuity without releasing an active callback's accounting. */
  private invalidate(): void {
    this.version++;
    for (const frame of this.pendingFrames) {
      this.pendingCount--;
      this.pendingBytes -= this.byteCount(frame);
    }
    this.pendingFrames = [];
    if (this.timer !== -1) {
      clearTimeout(this.timer);
      this.timer = -1;
    }

    this.audioTimeline.reset();
    this.audioDiscontinuous = true;
    this.videoDiscontinuous = true;
    this.lastVideoTimestampUs = undefined;
    this.lastVideoFormat = '';
  }

  /** Admits a packet, dropping new output when either retention limit would be exceeded. */
  private enqueue(
    frame: RealtimeMediaFrame
  ): boolean {
    const bytes: number = this.byteCount(frame);
    if (this.pendingCount >= this.maximumPendingFrames ||
      bytes > this.maximumPendingBytes - this.pendingBytes) {
      return false;
    }

    this.pendingFrames.push(frame);
    this.pendingCount++;
    this.pendingBytes += bytes;
    this.scheduleDelivery();
    return true;
  }

  /** Returns the media bytes retained by a queued packet. */
  private byteCount(
    frame: RealtimeMediaFrame
  ): number {
    if (frame.content instanceof RealtimeAudioFrame) {
      return frame.content.data.byteLength;
    }

    return frame.content.planes.reduce(
      (total: number, plane): number => total + plane.data.byteLength,
      0
    );
  }

  /** Schedules a delivery batch without reentering an application callback. */
  private scheduleDelivery(): void {
    if (this.timer !== -1 || this.delivering || this.pendingFrames.length === 0) {
      return;
    }

    const version: number = this.version;
    this.timer = setTimeout(
      (): void => this.deliver(version),
      0
    );
  }

  /** Delivers at most 16 packets per event-loop turn, invalidating the batch on lifecycle changes. */
  private deliver(
    version: number
  ): void {
    if (version !== this.version) {
      return;
    }

    this.timer = -1;
    this.delivering = true;
    try {
      for (let count: number = 0; count < 16 && this.pendingFrames.length > 0; count++) {
        if (version !== this.version || this.listener === null) {
          break;
        }

        const frame: RealtimeMediaFrame = this.pendingFrames.shift()!;
        const bytes: number = this.byteCount(frame);
        try {
          this.listener(frame);
        } catch (error) {
          XmaxLogger.error(
            'Remote media frame listener failed: ' + String(error),
            'Render'
          );
        } finally {
          this.pendingCount--;
          this.pendingBytes -= bytes;
        }
      }
    } finally {
      this.delivering = false;
      this.scheduleDelivery();
    }
  }
}
