//
//  AudioManager.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { audio } from '@kit.AudioKit';
import { XmaxLogger } from '../../logging/XmaxLogger';
import { AudioFrame } from './AudioFrame';
import { AudioManaging } from './AudioManaging';

/** Plays local PCM frames through the platform audio renderer. */
export class AudioManager implements AudioManaging {

  // Default volume configuration

  /** The default local preview volume in 0 to 1. */
  private static readonly DEFAULT_VOLUME: number = 0.45;

  // Player resources and volume

  /** The renderer used by this component. */
  private renderer: audio.AudioRenderer | null = null;

  /** The retained local playback volume in 0 to 1. */
  private configuredVolume: number = AudioManager.DEFAULT_VOLUME;

  // Serialized player operations

  /** The Promise serializing player volume and resource operations. */
  private pendingOperation: Promise<void> = Promise.resolve();

  // Pending playback queue and read position

  /** The media frames queued for asynchronous consumption. */
  private pendingFrames: Uint8Array[] = [];

  /** The byte offset into the currently consumed audio frame. */
  private pendingFrameOffset: number = 0;

  // Playback enablement and draining state

  /** Whether local audio preview is enabled. */
  private isPlaybackEnabled: boolean = true;

  /** The callbacks waiting for queued audio frames to drain. */
  private pendingFrameWaiters: Array<() => void> = [];

  /** Whether playback is draining queued audio without adding silence. */
  private isDraining: boolean = false;

  /**
   * Creates and starts a local PCM player.
   *
   * The Promise fulfills after playback starts.
   */
  start(): Promise<void> {
    return this.enqueueOperation((): Promise<void> => this.startRenderer());
  }

  /** Creates the system PCM player and binds the pending audio queue. */
  private async startRenderer(): Promise<void> {
    if (this.renderer !== null) {
      return;
    }

    const renderer: audio.AudioRenderer = await audio.createAudioRenderer({
      streamInfo: {
        samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_48000,
        channels: audio.AudioChannel.CHANNEL_1,
        sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
        encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
      },
      rendererInfo: {
        usage: audio.StreamUsage.STREAM_USAGE_MOVIE,
        rendererFlags: 0
      }
    });

    renderer.on(
      'writeData',
      (data: ArrayBuffer): audio.AudioDataCallbackResult => {
        return this.fillPlaybackBuffer(data);
      }
    );

    try {
      await renderer.setVolume(this.configuredVolume);
      await renderer.start();
      this.renderer = renderer;
    } catch (error) {
      const reason: string = error instanceof Error ? error.message : String(error);

      try {
        await renderer.release();
      } catch (releaseError) {
        const releaseReason: string = releaseError instanceof Error ?
          releaseError.message : String(releaseError);
        XmaxLogger.error(
          `${XmaxLogger.localized("释放本地音频播放器失败 (Failed to Release Local Audio Player)\n└─ 原因：", "释放本地音频播放器失败 (Failed to Release Local Audio Player)\n└─ Reason: ")}${releaseReason}`,
          'Audio'
        );
      }

      throw new Error(reason);
    }
  }

  /**
   * Queues a PCM frame for local playback.
   *
   * @param frame The PCM frame to play.
   */
  write(
    frame: AudioFrame
  ): void {
    if (this.renderer === null || !this.isPlaybackEnabled) {
      return;
    }

    this.pendingFrames.push(frame.data);
  }

  /**
   * Enables or pauses local audio preview. While paused, upstream audio processing continues but
   * the local player outputs silence.
   *
   * @param enabled Whether to play local preview audio.
   */
  setPlaybackEnabled(
    enabled: boolean
  ): void {
    if (this.isPlaybackEnabled === enabled) {
      return;
    }

    this.isPlaybackEnabled = enabled;
    if (!enabled) {
      this.clearPendingFrames();
    }
  }

  /** The configured local playback volume in 0 to 1; zero mutes and one uses original volume. */
  get volume(): number {
    return this.configuredVolume;
  }

  /**
   * Sets player volume in 0 to 1, retaining it after the player stops.
   *
   * @param volume The volume in 0 to 1, from muted to original volume.
   */
  setVolume(
    volume: number
  ): Promise<void> {
    return this.enqueueOperation(async (): Promise<void> => {
      if (this.renderer !== null) {
        await this.renderer.setVolume(volume);
      }
      this.configuredVolume = volume;
    });
  }

  /**
   * Serializes player operations to prevent resource access racing with startup or stopping.
   *
   * @param operation The operation to complete or clean up.
   */
  private enqueueOperation(
    operation: () => Promise<void>
  ): Promise<void> {
    const result: Promise<void> = this.pendingOperation.then(operation);
    this.pendingOperation = result.catch((): void => { });
    return result;
  }

  /**
   * Clears unplayed platform and local audio buffers.
   *
   * The Promise fulfills after buffered audio is cleared.
   */
  async flush(): Promise<void> {
    const renderer: audio.AudioRenderer | null = this.renderer;
    this.clearPendingFrames();

    if (renderer !== null) {
      await renderer.flush();
      this.clearPendingFrames();
    }
  }

  /** Waits for queued local audio playback without dropping its tail. */
  async drain(): Promise<void> {
    const renderer: audio.AudioRenderer | null = this.renderer;
    if (renderer === null || !this.isPlaybackEnabled) {
      return;
    }
    this.isDraining = true;
    try {
      if (this.pendingFrames.length > 0) {
        await new Promise<void>((resolve: () => void): void => {
          this.pendingFrameWaiters.push(resolve);
        });
      }
      if (this.renderer === renderer && this.isPlaybackEnabled) {
        await renderer.drain();
      }
    } finally {
      if (this.renderer === renderer) {
        this.isDraining = false;
      }
    }
  }

  /** Completes audio queue drain waits and releases pending callbacks. */
  private finishPendingFrameWaiters(): void {
    const waiters: Array<() => void> = this.pendingFrameWaiters;
    this.pendingFrameWaiters = [];
    waiters.forEach((resolve: () => void): void => { resolve(); });
  }

  /**
   * Stops local audio and releases platform resources.
   *
   * The Promise fulfills after the player stops.
   */
  stop(): Promise<void> {
    return this.enqueueOperation((): Promise<void> => this.stopRenderer());
  }

  /** Stops playback and releases the system audio player. */
  private async stopRenderer(): Promise<void> {
    const renderer: audio.AudioRenderer | null = this.renderer;
    this.renderer = null;
    this.isDraining = false;
    this.isPlaybackEnabled = true;
    this.clearPendingFrames();

    if (renderer === null) {
      return;
    }

    try {
      await renderer.stop();
    } catch (error) {
      const reason: string = error instanceof Error ? error.message : String(error);
      XmaxLogger.error(
        `${XmaxLogger.localized("停止本地音频播放器失败 (Failed to Stop Local Audio Player)\n└─ 原因：", "停止本地音频播放器失败 (Failed to Stop Local Audio Player)\n└─ Reason: ")}${reason}`,
        'Audio'
      );
    }

    try {
      await renderer.release();
    } catch (error) {
      const reason: string = error instanceof Error ? error.message : String(error);
      XmaxLogger.error(
        `${XmaxLogger.localized("释放本地音频播放器失败 (Failed to Release Local Audio Player)\n└─ 原因：", "释放本地音频播放器失败 (Failed to Release Local Audio Player)\n└─ Reason: ")}${reason}`,
        'Audio'
      );
    }
  }

  /**
   * Fills the platform playback buffer from queued audio frames.
   *
   * @param data The platform-supplied playback buffer.
   *
   * @returns The platform audio callback result.
   */
  private fillPlaybackBuffer(
    data: ArrayBuffer
  ): audio.AudioDataCallbackResult {
    // Do not keep padding silence while draining; otherwise the platform buffer cannot empty.
    if (this.isDraining && this.pendingFrames.length === 0) {
      return audio.AudioDataCallbackResult.INVALID;
    }
    const output = new Uint8Array(data);
    if (!this.isPlaybackEnabled) {
      output.fill(0);
      return audio.AudioDataCallbackResult.VALID;
    }

    let outputOffset: number = 0;

    while (outputOffset < output.length && this.pendingFrames.length > 0) {
      const frame: Uint8Array = this.pendingFrames[0];
      const availableLength: number = frame.length - this.pendingFrameOffset;
      const copyLength: number = Math.min(
        availableLength,
        output.length - outputOffset
      );

      output.set(
        frame.subarray(
          this.pendingFrameOffset,
          this.pendingFrameOffset + copyLength
        ),
        outputOffset
      );
      outputOffset += copyLength;
      this.pendingFrameOffset += copyLength;

      if (this.pendingFrameOffset === frame.length) {
        this.pendingFrames.shift();
        this.pendingFrameOffset = 0;
      }
    }

    if (outputOffset < output.length) {
      output.fill(
        0,
        outputOffset
      );
    }
    if (this.pendingFrames.length === 0) {
      this.finishPendingFrameWaiters();
    }

    return audio.AudioDataCallbackResult.VALID;
  }

  /** Clears queued frames and resets the current read offset. */
  private clearPendingFrames(): void {
    this.pendingFrames = [];
    this.pendingFrameOffset = 0;
    this.finishPendingFrameWaiters();
  }
}
