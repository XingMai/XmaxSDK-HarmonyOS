import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { RealtimeAudioFrame, RealtimeMediaFrame } from '@xmax/sdk';
import * as nativeRecorder from 'libxlab_recorder.so';

/** Records only SDK result media, without changing playback volume or capturing the microphone. */
export class RealtimeVideoRecorder {
  readonly outputPath: string;
  private handle: number | null = null;
  private streamId: string | undefined;
  private finishing: Promise<string> | null = null;

  constructor(context: common.Context) {
    this.outputPath = `${context.cacheDir}/xlab-recording-${util.generateRandomUUID()}.mp4`;
  }

  start(onError: (message: string) => void): void {
    if (this.handle !== null || this.finishing !== null) {
      throw new Error('Recording already started');
    }

    const handle: number = nativeRecorder.create(this.outputPath, (message: string): void => {
      if (this.handle === handle) {
        onError(message);
      }
    });
    this.handle = handle;
  }

  append(frame: RealtimeMediaFrame): void {
    if (this.handle === null) {
      return;
    }
    if (this.streamId !== undefined && this.streamId !== frame.streamId) {
      throw new Error('Generation result changed; start a new recording');
    }
    this.streamId = frame.streamId;

    if (frame.content instanceof RealtimeAudioFrame) {
      nativeRecorder.appendAudio(this.handle, frame.content);
    } else {
      nativeRecorder.appendVideo(this.handle, frame.content);
    }
  }

  stop(): Promise<string> {
    if (this.finishing !== null) {
      return this.finishing;
    }
    const handle: number | null = this.handle;
    if (handle === null) {
      return Promise.reject(new Error('Recording has not started'));
    }

    this.finishing = nativeRecorder.finish(handle, false);
    this.handle = null;
    return this.finishing;
  }

  /** Cancels unfinished work off the UI thread and removes this recorder's temporary output. */
  async cancel(): Promise<void> {
    const handle: number | null = this.handle;
    this.handle = null;
    try {
      if (handle !== null) {
        this.finishing = nativeRecorder.finish(handle, true);
      }
      await this.finishing;
    } catch (_error) {
      // Failed or cancelled recordings have no output to keep.
    } finally {
      await this.removeOutput();
    }
  }

  async removeOutput(): Promise<void> {
    try {
      await fileIo.unlink(this.outputPath);
    } catch (_error) {
      // The native recorder already removes failed output.
    }
  }

  /** Uses the system save dialog, without requesting broad photo-library access. */
  async saveToAlbum(context: common.Context): Promise<boolean> {
    const helper = photoAccessHelper.getPhotoAccessHelper(context);
    try {
      const destinations: string[] = await helper.showAssetsCreationDialog(
        [fileUri.getUriFromPath(this.outputPath)],
        [{ title: `XLab-${Date.now()}`, fileNameExtension: 'mp4', photoType: photoAccessHelper.PhotoType.VIDEO }]
      );
      if (destinations.length === 0 || destinations[0].length === 0) {
        return false;
      }

      const source = await fileIo.open(this.outputPath, fileIo.OpenMode.READ_ONLY);
      try {
        const destination = await fileIo.open(destinations[0], fileIo.OpenMode.WRITE_ONLY);
        try {
          await fileIo.copyFile(source.fd, destination.fd);
        } finally {
          await fileIo.close(destination);
        }
      } finally {
        await fileIo.close(source);
      }
      return true;
    } finally {
      await helper.release();
    }
  }
}
