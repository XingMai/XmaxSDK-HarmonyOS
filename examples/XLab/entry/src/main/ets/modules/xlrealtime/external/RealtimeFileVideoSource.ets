import {
  RealtimeExternalVideoSource, RealtimeExternalFrameSink, RealtimeVideoFormat,
  RealtimeVideoFrame, RealtimeAudioFrame, VideoFramePlane, VideoPixelFormat, VideoRotation
} from '@xmax/sdk';
import { createFileSource, FileFrame, FileSource } from 'libxlab_recorder.so';
import { fileIo } from '@kit.CoreFileKit';

/** App-owned system decoding; XmaxSDK only receives frames through the public external sink. */
export class RealtimeFileVideoSource implements RealtimeExternalVideoSource {
  readonly videoFormat: RealtimeVideoFormat;
  readonly hasAudio: boolean;
  private readonly decoder: FileSource;
  private sink: RealtimeExternalFrameSink | null = null;
  private stopping: Promise<void> | null = null;

  private constructor(decoder: FileSource, fps: number) {
    this.decoder = decoder;
    this.videoFormat = new RealtimeVideoFormat(decoder.width, decoder.height, fps);
    this.hasAudio = decoder.hasAudio;
  }

  /** Opens file metadata on a native worker; decoding starts only after the sink is installed. */
  static async create(path: string, fps: number, maximumPixels: number): Promise<RealtimeFileVideoSource> {
    let source: RealtimeFileVideoSource | null = null;
    const file: fileIo.File = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
    try {
      const size: number = (await fileIo.stat(file.fd)).size;
      const decoder: FileSource = await createFileSource(file.fd, size, maximumPixels, fps, (frame: FileFrame): void => {
        source?.receive(frame);
      });
      source = new RealtimeFileVideoSource(decoder, fps);
      return source;
    } finally {
      await fileIo.close(file);
    }
  }

  async start(sink: RealtimeExternalFrameSink): Promise<void> {
    if (this.stopping !== null) {
      throw new Error('This file source has already stopped; create a new source');
    }
    this.sink = sink;
    this.decoder.start();
  }

  /** Detaches callbacks immediately and waits for native decoding cleanup off the UI thread. */
  stop(): Promise<void> {
    this.sink = null;
    if (this.stopping === null) {
      this.stopping = this.decoder.release();
    }
    return this.stopping;
  }

  private receive(frame: FileFrame): void {
    const sink: RealtimeExternalFrameSink | null = this.sink;
    if (sink === null || !sink.isRequestingFrames) {
      return;
    }
    if (frame.error !== undefined) {
      sink.reportError(new Error(frame.error));
      return;
    }

    if (frame.video) {
      const ySize: number = frame.width * frame.height;
      sink.pushVideo(new RealtimeVideoFrame(frame.width, frame.height, VideoPixelFormat.NV12,
        [new VideoFramePlane(frame.data, frame.width, 0, ySize),
          new VideoFramePlane(frame.data, frame.width, ySize, ySize / 2)],
        frame.timestampUs, VideoRotation.ROTATION_0));
    } else {
      sink.pushAudio(new RealtimeAudioFrame(new Uint8Array(frame.data), frame.sampleRate, frame.channels,
        frame.data.byteLength / (2 * frame.channels), frame.timestampUs));
    }
  }
}
