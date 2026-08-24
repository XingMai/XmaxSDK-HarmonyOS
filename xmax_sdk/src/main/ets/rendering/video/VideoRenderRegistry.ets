import { image } from '@kit.ImageKit';
import { VideoContentMode } from '../../foundation/media/video/VideoContentMode';
import { resolveStateTarget } from '../../foundation/state/StateTargetResolver';
import { RealtimeVideoTrack } from '../../service/realtime/RealtimeVideoTrack';
import { CameraPreviewRatio } from './CameraPreviewRatio';

type CameraPreviewRatioListener = (ratio: CameraPreviewRatio) => void;
type PreviewFrameListener = (frame: image.PixelMap | undefined) => void;

interface AttachedVideoView {
  contentMode: VideoContentMode;
  previewRatioListener: CameraPreviewRatioListener;
  previewFrameListener: PreviewFrameListener;
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
    previewFrameListener: PreviewFrameListener
  ): void {
    this.attachedViews.set(viewId, {
      contentMode: contentMode,
      previewRatioListener: previewRatioListener,
      previewFrameListener: previewFrameListener
    });

    const previewRatio: CameraPreviewRatio | undefined = this.previewRatio;
    if (previewRatio !== undefined) {
      previewRatioListener(previewRatio);
    }
    previewFrameListener(this.previewFrame);

    this.attachHandler(viewId, contentMode);
  }

  detach(viewId: string): void {
    this.attachedViews.delete(viewId);
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
    VideoRenderRegistry.bindings.set(resolveStateTarget(track), binding);
  }

  static unregister(track: RealtimeVideoTrack): void {
    VideoRenderRegistry.bindings.delete(resolveStateTarget(track));
  }

  static libraryName(track: RealtimeVideoTrack): string {
    return VideoRenderRegistry.bindings.get(resolveStateTarget(track))?.libraryName ?? '';
  }

  static cameraPreviewRatio(track: RealtimeVideoTrack): CameraPreviewRatio | undefined {
    return VideoRenderRegistry.bindings.get(resolveStateTarget(track))?.cameraPreviewRatio();
  }

  static setPreviewFrame(
    track: RealtimeVideoTrack,
    frame?: image.PixelMap
  ): void {
    VideoRenderRegistry.bindings.get(resolveStateTarget(track))?.setPreviewFrame(frame);
  }

  static attach(
    track: RealtimeVideoTrack,
    viewId: string,
    contentMode: VideoContentMode,
    previewRatioListener: CameraPreviewRatioListener,
    previewFrameListener: PreviewFrameListener
  ): void {
    VideoRenderRegistry.bindings.get(resolveStateTarget(track))?.attach(
      viewId,
      contentMode,
      previewRatioListener,
      previewFrameListener
    );
  }

  static setContentMode(
    track: RealtimeVideoTrack,
    viewId: string,
    contentMode: VideoContentMode
  ): void {
    VideoRenderRegistry.bindings.get(resolveStateTarget(track))?.setContentMode(
      viewId,
      contentMode
    );
  }

  static detach(
    track: RealtimeVideoTrack,
    viewId: string
  ): void {
    VideoRenderRegistry.bindings.get(resolveStateTarget(track))?.detach(viewId);
  }
}
