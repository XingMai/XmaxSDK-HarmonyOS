//
//  AudioFileFrameDecoder.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { fileIo } from '@kit.CoreFileKit';
import xmaxVideoNative, {
  NativeAudioFileDecoder
} from 'libxmax_video.so';
import { AudioFrame } from './AudioFrame';

/** Continuous audio file decoding events. */
export interface AudioFileFrameDecoderListener {

  /**
   * Receives decoded frames on the media timeline.
   *
   * @param frame The decoded audio frame.
   */
  onFrame(
    frame: AudioFrame
  ): void;

  /** Reports completion of the current file's decoded output. */
  onEndOfStream(): void;

  /**
   * Reports a decoding or frame delivery failure.
   *
   * @param message The error message.
   */
  onError(
    message: string
  ): void;
}

/** Decodes continuous audio into 48 kHz mono PCM frames. */
export class AudioFileFrameDecoder {

  /** The native file decoder owned by this wrapper. */
  private readonly nativeDecoder: NativeAudioFileDecoder;

  /** Whether the owned resource has been released. */
  private isReleased: boolean = false;

  /**
   * Creates an audio file decoder.
   *
   * @param filePath The local media file path.
   * @param playbackAnchorUs The monotonic playback time for the media origin, in microseconds.
   * @param mediaStartUs The media timeline origin, in microseconds.
   * @param cycleDurationUs The playback cycle duration, in microseconds.
   * @param listener The handler for decoded PCM frames, file completion, and decoding failures.
   */
  constructor(
    filePath: string,
    playbackAnchorUs: number,
    mediaStartUs: number,
    cycleDurationUs: number,
    listener: AudioFileFrameDecoderListener
  ) {
    const sourceFile: fileIo.File = fileIo.openSync(
      filePath,
      fileIo.OpenMode.READ_ONLY
    );

    try {
      const sourceSize: number = fileIo.statSync(sourceFile.fd).size;
      this.nativeDecoder = xmaxVideoNative.createAudioFileDecoder(
        sourceFile.fd,
        sourceSize,
        playbackAnchorUs,
        mediaStartUs,
        cycleDurationUs,
        (
          data: ArrayBuffer | undefined,
          timestampUs: number,
          endOfStream: boolean,
          error?: string
        ): void => {
          if (this.isReleased) {
            return;
          }
          if (error !== undefined && error.length > 0) {
            listener.onError(error);
            return;
          }
          if (endOfStream) {
            listener.onEndOfStream();
            return;
          }

          if (data !== undefined) {
            listener.onFrame(new AudioFrame(
              new Uint8Array(data),
              timestampUs
            ));
          }
        }
      );
    } finally {
      fileIo.closeSync(sourceFile);
    }
  }

  /** Pauses continuous file audio decoding. */
  pause(): void {
    if (!this.isReleased) {
      this.nativeDecoder.pause();
    }
  }

  /**
   * Resumes audio decoding with the playback anchor shifted by the pause duration.
   *
   * @param pausedDurationUs The pause duration, in microseconds.
   */
  resume(
    pausedDurationUs: number
  ): void {
    if (!this.isReleased) {
      this.nativeDecoder.resume(pausedDurationUs);
    }
  }

  /** Stops audio callbacks and releases native decoding resources. */
  release(): void {
    if (this.isReleased) {
      return;
    }

    this.isReleased = true;
    this.nativeDecoder.release();
  }
}
