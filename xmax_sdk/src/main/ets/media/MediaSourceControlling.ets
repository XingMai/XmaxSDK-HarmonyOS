//
//  MediaSourceControlling.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { RealtimeVideoFormat } from '../service/realtime/RealtimeVideoFormat';
import { MediaSourceConfiguration } from './MediaSourceConfiguration';

/** An interface for local file audio/video input. */
export interface MediaSourceControlling {

  /** The local file preview volume in 0 to 1; defaults to 0.45. */
  readonly localAudioVolume: number;

  /** Whether the file contains an available audio track. */
  readonly hasAudio: boolean;

  /** Whether file playback ended naturally and local audio finished draining. */
  readonly hasEnded: boolean;

  /**
   * Prepares the local file and output format.
   *
   * @param filePath The local media file path.
   * @param videoFormat The requested format, resolved from file metadata if omitted.
   * @param loop Whether to loop after file completion.
   *
   * @returns The resolved media source configuration.
   */
  prepare(
    filePath: string,
    videoFormat?: RealtimeVideoFormat,
    loop?: boolean
  ): Promise<MediaSourceConfiguration>;

  /**
   * Starts synchronized file audio/video output.
   *
   * The Promise fulfills after media source startup.
   */
  start(): Promise<void>;

  /** Pauses the file timeline and clears buffered local audio. */
  pause(): Promise<void>;

  /** Resumes the file timeline at its paused media position. */
  resume(): void;

  /**
   * Enables local audio preview without affecting RTC audio output.
   *
   * @param enabled Whether to play local preview audio.
   */
  setLocalAudioPreviewEnabled(
    enabled: boolean
  ): void;

  /**
   * Sets preview volume without changing audio frames for other consumers.
   *
   * @param volume The volume in 0 to 1, from muted to original volume.
   */
  setLocalAudioVolume(
    volume: number
  ): Promise<void>;

  /**
   * Stops output and releases media file resources.
   *
   * The Promise fulfills after media source stopping.
   */
  stop(): Promise<void>;
}
