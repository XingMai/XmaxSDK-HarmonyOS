//
//  AudioSourceController.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import {
  AudioFileFrameDecoder,
  AudioFileFrameDecoderListener
} from '../../foundation/media/audio/AudioFileFrameDecoder';
import { AudioFrame } from '../../foundation/media/audio/AudioFrame';
import { XmaxError, XmaxErrorCode } from '../../foundation/errors/XmaxError';
import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import { MediaTimeline } from '../MediaTimeline';
import { AudioSourceControlling } from './AudioSourceControlling';

/**
 * Receives PCM decoded by a local audio source.
 *
 * @param frame The decoded 48 kHz mono PCM frame on the local audio playback timeline.
 */
export type AudioSourceFrameListener = (
  frame: AudioFrame
) => void;

/**
 * Receives local audio configuration or decoding errors.
 *
 * @param message The local audio configuration or decoding failure description.
 */
export type AudioSourceErrorListener = (
  message: string
) => void;

/** Decodes file audio on a shared timeline with optional looping. */
export class AudioSourceController implements AudioSourceControlling {

  // Frame and error notifications

  /** The receiver for prepared media frames. */
  private readonly frameListener: AudioSourceFrameListener;

  /** The handler for asynchronous component failures. */
  private readonly errorListener: AudioSourceErrorListener;

  // File decoding and loop timeline

  /** The native file decoder for the current playback cycle. */
  private decoder: AudioFileFrameDecoder | null = null;

  /** The local media file path. */
  private filePath: string = '';

  // Playback progress

  /** The playback timeline shared by audio and video. */
  private timeline: MediaTimeline | null = null;

  /** The zero-based playback cycle index. */
  private loopIndex: number = 0;

  // Pause, looping, and file completion state

  /** Whether media output is paused. */
  private isPaused: boolean = false;

  /** Whether completion arrived while playback was paused. */
  private pendingEndOfStream: boolean = false;

  /** Whether file playback restarts after natural completion. */
  private loop: boolean = true;

  /** Whether non-looping media output has ended naturally. */
  private hasEnded: boolean = false;

  // Audio source revision and playback completion

  /** The revision rejecting output from obsolete file sources. */
  private sourceVersion: number = 0;

  /** Reports local media playback completion. */
  private readonly endedListener: () => void;

  /** Creates an audio source controller. */
  constructor(
    frameListener: AudioSourceFrameListener,
    errorListener: AudioSourceErrorListener,
    endedListener: () => void = (): void => { }
  ) {
    this.frameListener = frameListener;
    this.errorListener = errorListener;
    this.endedListener = endedListener;
  }

  /**
   * Configures the local file to decode.
   *
   * @param filePath The local media file path.
   * @param loop Whether to loop after file completion.
   */
  configure(
    filePath: string,
    loop: boolean = true
  ): void {
    if (this.decoder !== null) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Stop the current audio source before configuring another file'
      );
    }

    this.filePath = filePath;
    this.loop = loop;
  }

  /**
   * Starts audio frame output on the shared timeline.
   *
   * @param timeline The shared audio/video playback timeline.
   */
  start(
    timeline: MediaTimeline
  ): void {
    if (this.filePath.length === 0) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Configure the local media file before starting the audio source'
      );
    }
    if (this.decoder !== null) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Local audio source is already active'
      );
    }

    this.timeline = timeline;
    this.sourceVersion++;
    this.hasEnded = false;
    this.loopIndex = 0;
    this.isPaused = false;
    this.pendingEndOfStream = false;

    this.decoder = this.createDecoder();
  }

  /** Pauses the decoder while retaining media position and resources. */
  pause(): void {
    if (this.hasEnded) {
      return;
    }
    if (this.isPaused) {
      return;
    }

    const decoder: AudioFileFrameDecoder | null = this.decoder;
    if (decoder === null) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Local audio source is not active'
      );
    }

    this.isPaused = true;
    decoder.pause();
  }

  /**
   * Resumes the decoder with the shared pause duration.
   *
   * @param pausedDurationUs The pause duration, in microseconds.
   */
  resume(
    pausedDurationUs: number
  ): void {
    if (this.hasEnded) {
      return;
    }
    if (!this.isPaused) {
      return;
    }

    const decoder: AudioFileFrameDecoder | null = this.decoder;
    if (decoder === null) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Local audio source is not active'
      );
    }

    decoder.resume(pausedDurationUs);
    this.isPaused = false;

    if (this.pendingEndOfStream) {
      this.pendingEndOfStream = false;
      this.handleEndOfStream(this.loopIndex);
    }
  }

  /** Stops output and clears audio file state. */
  stop(): void {
    this.sourceVersion++;
    this.hasEnded = false;

    this.releaseDecoder();

    this.filePath = '';
    this.timeline = null;
    this.loopIndex = 0;
    this.isPaused = false;
    this.pendingEndOfStream = false;
  }

  /**
   * Creates an audio frame decoder for the current file and timeline.
   *
   * @returns The started audio frame decoder.
   */
  private createDecoder(): AudioFileFrameDecoder {
    const timeline: MediaTimeline | null = this.timeline;
    if (timeline === null) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Audio source timeline is unavailable'
      );
    }

    const loopIndex: number = this.loopIndex;
    const version: number = this.sourceVersion;
    return new AudioFileFrameDecoder(
      this.filePath,
      timeline.playbackAnchorForLoop(loopIndex),
      timeline.mediaStartUs,
      timeline.cycleDurationUs,
      new AudioSourceDecoderListener(
        (frame: AudioFrame): void => {
          if (version === this.sourceVersion && !this.isPaused && !this.hasEnded) {
            this.frameListener(frame);
          }
        },
        (): void => {
          if (version === this.sourceVersion) {
            this.handleEndOfStream(loopIndex);
          }
        },
        (message: string): void => {
          if (version === this.sourceVersion) {
            this.errorListener(message);
          }
        }
      )
    );
  }

  /**
   * Creates the next audio decoder after a playback cycle ends.
   *
   * @param loopIndex The completed decoder's playback cycle index.
   */
  private handleEndOfStream(
    loopIndex: number
  ): void {
    const endedDecoder: AudioFileFrameDecoder | null = this.decoder;
    if (endedDecoder === null || loopIndex !== this.loopIndex || this.hasEnded) {
      return;
    }
    if (this.isPaused) {
      this.pendingEndOfStream = true;
      return;
    }

    setTimeout(
      (): void => {
        if (this.decoder !== endedDecoder || loopIndex !== this.loopIndex) {
          return;
        }
        if (this.isPaused) {
          this.pendingEndOfStream = true;
          return;
        }

        this.decoder = null;
        this.releaseDecoderInstance(endedDecoder);
        if (!this.loop) {
          this.hasEnded = true;
          this.endedListener();
          return;
        }

        this.loopIndex++;

        try {
          this.decoder = this.createDecoder();
        } catch (error) {
          const reason: string = error instanceof Error ? error.message : String(error);
          this.errorListener(reason);
        }
      },
      0
    );
  }

  /** Releases the current audio decoder. */
  private releaseDecoder(): void {
    const decoder: AudioFileFrameDecoder | null = this.decoder;
    this.decoder = null;

    if (decoder !== null) {
      this.releaseDecoderInstance(decoder);
    }
  }

  /**
   * Releases an audio decoder and logs release errors.
   *
   * @param decoder The audio decoder to release.
   */
  private releaseDecoderInstance(
    decoder: AudioFileFrameDecoder
  ): void {
    try {
      decoder.release();
    } catch (error) {
      const reason: string = error instanceof Error ? error.message : String(error);
      XmaxLogger.error(
        `${XmaxLogger.localized("释放本地音频解码器失败 (Failed to Release Local Audio Decoder)\n└─ 原因：", "释放本地音频解码器失败 (Failed to Release Local Audio Decoder)\n└─ Reason: ")}${reason}`,
        'Audio'
      );
    }
  }
}

/** Forwards audio decoder events to the source controller. */
class AudioSourceDecoderListener implements AudioFileFrameDecoderListener {

  /**
   * Delivers a decoded frame for the current source.
   *
   * @param frame The decoded PCM frame.
   */
  private readonly frameHandler: (
    frame: AudioFrame
  ) => void;

  /** Reports that the source reached the file end. */
  private readonly endHandler: () => void;

  /**
   * Delivers source decoding or output errors.
   *
   * @param message The local audio decoding or output failure description.
   */
  private readonly errorHandler: (
    message: string
  ) => void;

  /** Creates an audio decoder event adapter. */
  constructor(
    frameHandler: (
      frame: AudioFrame
    ) => void,
    endHandler: () => void,
    errorHandler: (
      message: string
    ) => void
  ) {
    this.frameHandler = frameHandler;
    this.endHandler = endHandler;
    this.errorHandler = errorHandler;
  }

  /**
   * Forwards decoded audio and reports frame handler exceptions.
   *
   * @param frame The decoded audio frame.
   */
  onFrame(
    frame: AudioFrame
  ): void {
    try {
      this.frameHandler(frame);
    } catch (error) {
      const reason: string = error instanceof Error ? error.message : String(error);
      this.errorHandler(`${XmaxLogger.localized("处理本地音频帧失败：", "Local Audio Frame Processing Failed: ")}${reason}`);
    }
  }

  /** Forwards audio completion. */
  onEndOfStream(): void {
    this.endHandler();
  }

  /**
   * Forwards audio decoding errors.
   *
   * @param message The error message.
   */
  onError(
    message: string
  ): void {
    this.errorHandler(message);
  }
}
