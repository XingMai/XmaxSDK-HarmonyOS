import { image } from '@kit.ImageKit';
import { VideoContentMode } from '../../foundation/media/video/VideoContentMode';
import { RealtimeVideoTrack } from '../../service/realtime/RealtimeVideoTrack';
import { CameraPreviewRatio } from './CameraPreviewRatio';

type CameraPreviewRatioListener = (ratio: CameraPreviewRatio) => void;
export type VideoReadyListener = (ready: boolean) => void;

type PreviewFrameListener = (frame: image.PixelMap | undefined) => void;
type VideoFormatListener = () => void;

interface AttachedVideoView {
  contentMode: VideoContentMode;
  previewRatioListener: CameraPreviewRatioListener;
  previewFrameListener: PreviewFrameListener;
  videoReadyListener?: VideoReadyListener;
  videoFormatListener?: VideoFormatListener;
}

export class VideoRenderBinding {
  readonly libraryName: string;
  private readonly attachHandler: (
    viewId: string,
    contentMode: VideoContentMode
  ) => void;
  private readonly detachHandler: (viewId: string) => void;
  private readonly attachedViews: Map<string, AttachedVideoView> = new Map();
  private previewRatio?: CameraPreviewRatio;
  private previewFrame?: image.PixelMap;
  private videoReady: boolean = false;

  constructor(
    libraryName: string,
    attachHandler: (
      viewId: string,
      contentMode: VideoContentMode
    ) => void,
    detachHandler: (viewId: string) => void,
    previewRatio?: CameraPreviewRatio
  ) {
    this.libraryName = libraryName;
    this.attachHandler = attachHandler;
    this.detachHandler = detachHandler;
    this.previewRatio = previewRatio;
  }

  attach(
    viewId: string,
    contentMode: VideoContentMode,
    previewRatioListener: CameraPreviewRatioListener,
    previewFrameListener: PreviewFrameListener,
    videoReadyListener?: VideoReadyListener,
    videoFormatListener?: VideoFormatListener
  ): void {
    this.attachedViews.set(viewId, {
      contentMode: contentMode,
      previewRatioListener: previewRatioListener,
      previewFrameListener: previewFrameListener,
      videoReadyListener: videoReadyListener,
      videoFormatListener: videoFormatListener
    });

    const previewRatio: CameraPreviewRatio | undefined = this.previewRatio;
    if (previewRatio !== undefined) {
      previewRatioListener(previewRatio);
    }
    previewFrameListener(this.previewFrame);
    videoReadyListener?.(this.videoReady);
    videoFormatListener?.();

    this.attachHandler(viewId, contentMode);
  }

  detach(viewId: string): void {
    const view: AttachedVideoView | undefined = this.attachedViews.get(viewId);
    if (view === undefined) {
      return;
    }
    this.attachedViews.delete(viewId);
    view.videoReadyListener?.(false);
    this.detachHandler(viewId);
  }

  setContentMode(
    viewId: string,
    contentMode: VideoContentMode
  ): void {
    const attachedView: AttachedVideoView | undefined = this.attachedViews.get(viewId);
    if (attachedView === undefined || attachedView.contentMode === contentMode) {
      return;
    }

    attachedView.contentMode = contentMode;
    this.attachHandler(viewId, contentMode);
  }

  setVideoReady(ready: boolean): void {
    if (this.videoReady === ready) {
      return;
    }
    this.videoReady = ready;
    this.attachedViews.forEach((view: AttachedVideoView): void => {
      view.videoReadyListener?.(ready);
    });
  }

  notifyVideoFormatChanged(): void {
    this.attachedViews.forEach((view: AttachedVideoView): void => view.videoFormatListener?.());
  }

  dispose(): void {
    this.setPreviewFrame(undefined);
    this.setVideoReady(false);
    this.attachedViews.forEach((_view: AttachedVideoView, viewId: string): void => {
      this.detach(viewId);
    });
  }

  cameraPreviewRatio(): CameraPreviewRatio | undefined {
    return this.previewRatio;
  }

  setPreviewFrame(frame?: image.PixelMap): void {
    this.previewFrame = frame;
    this.attachedViews.forEach((attachedView: AttachedVideoView): void => {
      attachedView.previewFrameListener(frame);
    });
  }
}

export class VideoRenderRegistry {
  private static readonly bindings: Map<RealtimeVideoTrack, VideoRenderBinding> = new Map();

  static register(
    track: RealtimeVideoTrack,
    binding: VideoRenderBinding
  ): void {
    VideoRenderRegistry.bindings.set(RealtimeVideoTrack.resolve(track), binding);
  }

  static unregister(track: RealtimeVideoTrack): void {
    const originalTrack: RealtimeVideoTrack = RealtimeVideoTrack.resolve(track);
    VideoRenderRegistry.bindings.get(originalTrack)?.dispose();
    VideoRenderRegistry.bindings.delete(originalTrack);
  }

  static libraryName(track: RealtimeVideoTrack): string {
    return VideoRenderRegistry.bindings.get(RealtimeVideoTrack.resolve(track))?.libraryName ?? '';
  }

  static cameraPreviewRatio(track: RealtimeVideoTrack): CameraPreviewRatio | undefined {
    return VideoRenderRegistry.bindings.get(RealtimeVideoTrack.resolve(track))?.cameraPreviewRatio();
  }

  static setPreviewFrame(
    track: RealtimeVideoTrack,
    frame?: image.PixelMap
  ): void {
    VideoRenderRegistry.bindings.get(RealtimeVideoTrack.resolve(track))?.setPreviewFrame(frame);
  }

  static attach(
    track: RealtimeVideoTrack,
    viewId: string,
    contentMode: VideoContentMode,
    previewRatioListener: CameraPreviewRatioListener,
    previewFrameListener: PreviewFrameListener,
    videoReadyListener?: VideoReadyListener,
    videoFormatListener?: VideoFormatListener
  ): void {
    VideoRenderRegistry.bindings.get(RealtimeVideoTrack.resolve(track))?.attach(
      viewId,
      contentMode,
      previewRatioListener,
      previewFrameListener,
      videoReadyListener,
      videoFormatListener
    );
  }

  static notifyVideoFormatChanged(track: RealtimeVideoTrack): void {
    VideoRenderRegistry.bindings.get(RealtimeVideoTrack.resolve(track))?.notifyVideoFormatChanged();
  }

  static setContentMode(
    track: RealtimeVideoTrack,
    viewId: string,
    contentMode: VideoContentMode
  ): void {
    VideoRenderRegistry.bindings.get(RealtimeVideoTrack.resolve(track))?.setContentMode(
      viewId,
      contentMode
    );
  }

  static detach(
    track: RealtimeVideoTrack,
    viewId: string
  ): void {
    VideoRenderRegistry.bindings.get(RealtimeVideoTrack.resolve(track))?.detach(viewId);
  }
}
