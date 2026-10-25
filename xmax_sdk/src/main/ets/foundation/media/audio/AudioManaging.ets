//
//  AudioManaging.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { AudioFrame } from './AudioFrame';

/** An interface for local PCM playback. */
export interface AudioManaging {

  /** The configured local playback volume in 0 to 1; defaults to 0.45. */
  readonly volume: number;

  /**
   * Creates and starts a local PCM player.
   *
   * The Promise fulfills after playback starts.
   */
  start(): Promise<void>;

  /**
   * Queues a local preview audio frame.
   *
   * @param frame The PCM frame to play.
   */
  write(
    frame: AudioFrame
  ): void;

  /**
   * Enables or pauses local audio preview without affecting other frame consumers.
   *
   * @param enabled Whether to play local preview audio.
   */
  setPlaybackEnabled(
    enabled: boolean
  ): void;

  /**
   * Sets player volume in 0 to 1, retaining it after the player stops.
   *
   * @param volume The volume in 0 to 1, from muted to original volume.
   */
  setVolume(
    volume: number
  ): Promise<void>;

  /**
   * Clears unplayed audio data.
   *
   * The Promise fulfills after buffered audio is cleared.
   */
  flush(): Promise<void>;

  /** Waits for queued local audio playback without dropping its tail. */
  drain(): Promise<void>;

  /**
   * Stops local audio playback and releases resources.
   *
   * The Promise fulfills after the player stops.
   */
  stop(): Promise<void>;
}
