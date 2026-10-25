//
//  VideoRenderRegistry.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { image } from '@kit.ImageKit';
import { VideoContentMode } from '../../foundation/media/video/VideoContentMode';
import { RealtimeVideoTrack } from '../../service/realtime/RealtimeVideoTrack';
import { CameraPreviewRatio } from './CameraPreviewRatio';

/**
 * Receives camera preview aspect ratio updates.
 *
 * @param ratio The camera preview aspect ratio.
 */
type CameraPreviewRatioListener = (
  ratio: CameraPreviewRatio
) => void;

/**
 * Receives changes to displayed video readiness.
 *
 * @param ready Whether video is visible.
 */
export type VideoReadyListener = (
  ready: boolean
) => void;

/**
 * Receives preview image updates; an absent value clears preview.
 *
 * @param frame The local preview PixelMap, or undefined to clear the displayed image.
 */
type PreviewFrameListener = (
  frame: image.PixelMap | undefined
) => void;

/** Requests view layout updates after track format changes. */
type VideoFormatListener = () => void;

/** A bound view's content mode and preview, readiness, and format listeners. */
interface AttachedVideoView {

  // View display configuration

  /** The aspect-fit or aspect-fill display mode. */
  contentMode: VideoContentMode;

  // Preview, readiness, and format notifications

  /** The camera preview aspect ratio handler. */
  previewRatioListener: CameraPreviewRatioListener;

  /** The preview image update and clearing handler. */
  previewFrameListener: PreviewFrameListener;

  /** The displayed video readiness handler. */
  videoReadyListener?: VideoReadyListener;

  /** The track format change handler. */
  videoFormatListener?: VideoFormatListener;
}

/** Manages a track's bound views and broadcasts preview and display state. */
export class VideoRenderBinding {

  // Native rendering binding dependencies

  /** The native library used by the rendering Surface. */
  readonly libraryName: string;

  /**
   * Binds a stream to a native video view.
   *
   * @param viewId The native video view identifier.
   * @param contentMode The aspect-fit or aspect-fill content mode.
   */
  private readonly attachHandler: (
    viewId: string,
    contentMode: VideoContentMode
  ) => void;

  /**
   * Detaches a native video view's stream.
   *
   * @param viewId The native video view identifier.
   */
  private readonly detachHandler: (
    viewId: string
  ) => void;

  // Bound view records

  /** The bound views and their rendering listeners. */
  private readonly attachedViews: Map<string, AttachedVideoView> = new Map();

  // Shared preview and video readiness state

  /** The configured camera preview aspect ratio. */
  private previewRatio?: CameraPreviewRatio;

  /** The retained preview or frozen result image. */
  private previewFrame?: image.PixelMap;

  /** Whether the bound video is ready to display. */
  private videoReady: boolean = false;

  /** Creates a video track rendering binding. */
  constructor(
    libraryName: string,
    attachHandler: (
      viewId: string,
      contentMode: VideoContentMode
    ) => void,
    detachHandler: (
      viewId: string
    ) => void,
    previewRatio?: CameraPreviewRatio
  ) {
    this.libraryName = libraryName;
    this.attachHandler = attachHandler;
    this.detachHandler = detachHandler;
    this.previewRatio = previewRatio;
  }

  /**
   * Attaches a view and synchronizes preview, readiness, and display settings.
   *
   * @param viewId The native video view identifier.
   * @param contentMode The aspect-fit or aspect-fill content mode.
   * @param previewRatioListener The camera preview ratio handler.
   * @param previewFrameListener The preview image update or clearing handler.
   * @param videoReadyListener The video readiness handler.
   * @param videoFormatListener The track format change handler.
   */
  attach(
    viewId: string,
    contentMode: VideoContentMode,
    previewRatioListener: CameraPreviewRatioListener,
    previewFrameListener: PreviewFrameListener,
    videoReadyListener?: VideoReadyListener,
    videoFormatListener?: VideoFormatListener
  ): void {
    this.attachedViews.set(
      viewId,
      {
        contentMode: contentMode,
        previewRatioListener: previewRatioListener,
        previewFrameListener: previewFrameListener,
        videoReadyListener: videoReadyListener,
        videoFormatListener: videoFormatListener
      }
    );

    const previewRatio: CameraPreviewRatio | undefined = this.previewRatio;
    if (previewRatio !== undefined) {
      previewRatioListener(previewRatio);
    }
    previewFrameListener(this.previewFrame);
    videoReadyListener?.(this.videoReady);
    videoFormatListener?.();

    this.attachHandler(
      viewId,
      contentMode
    );
  }

  /**
   * Detaches a view and stops its rendering notifications.
   *
   * @param viewId The rendering container identifier.
   */
  detach(
    viewId: string
  ): void {
    const view: AttachedVideoView | undefined = this.attachedViews.get(viewId);
    if (view === undefined) {
      return;
    }
    this.attachedViews.delete(viewId);
    view.videoReadyListener?.(false);
    this.detachHandler(viewId);
  }

  /**
   * Updates a view's video content mode.
   *
   * @param viewId The native video view identifier.
   * @param contentMode The aspect-fit or aspect-fill content mode.
   */
  setContentMode(
    viewId: string,
    contentMode: VideoContentMode
  ): void {
    const attachedView: AttachedVideoView | undefined = this.attachedViews.get(viewId);
    if (attachedView === undefined || attachedView.contentMode === contentMode) {
      return;
    }

    attachedView.contentMode = contentMode;
    this.attachHandler(
      viewId,
      contentMode
    );
  }

  /**
   * Updates and broadcasts video visibility readiness.
   *
   * @param ready Whether video is visible.
   */
  setVideoReady(
    ready: boolean
  ): void {
    if (this.videoReady === ready) {
      return;
    }
    this.videoReady = ready;
    this.attachedViews.forEach((view: AttachedVideoView): void => {
      view.videoReadyListener?.(ready);
    });
  }

  /** Notifies bound views to refresh track format and layout. */
  notifyVideoFormatChanged(): void {
    this.attachedViews.forEach((view: AttachedVideoView): void => view.videoFormatListener?.());
  }

  /** Detaches all views and releases their callbacks. */
  dispose(): void {
    this.setPreviewFrame(undefined);
    this.setVideoReady(false);
    this.attachedViews.forEach((_view: AttachedVideoView, viewId: string): void => {
      this.detach(viewId);
    });
  }

  /**
   * Returns the track's camera preview aspect ratio.
   *
   * @returns The preview ratio, or undefined for non-camera tracks or absent configuration.
   */
  cameraPreviewRatio(): CameraPreviewRatio | undefined {
    return this.previewRatio;
  }

  /**
   * Updates and broadcasts the preview image; an absent value clears it.
   *
   * @param frame The local preview PixelMap, or undefined to clear the displayed image.
   */
  setPreviewFrame(
    frame?: image.PixelMap
  ): void {
    this.previewFrame = frame;
    this.attachedViews.forEach((attachedView: AttachedVideoView): void => {
      attachedView.previewFrameListener(frame);
    });
  }
}

/** A track rendering registry connecting media controllers to ArkUI video views. */
export class VideoRenderRegistry {

  // Weak track-to-rendering bindings

  /** The weak mappings from original tracks to their resource bindings. */
  private static readonly bindings: Map<RealtimeVideoTrack, VideoRenderBinding> = new Map();

  /**
   * Registers a track and its resource binding.
   *
   * @param track The SDK video track handle.
   * @param binding The resource binding to associate with the track.
   */
  static register(
    track: RealtimeVideoTrack,
    binding: VideoRenderBinding
  ): void {
    VideoRenderRegistry.bindings.set(
      RealtimeVideoTrack.resolve(track),
      binding
    );
  }

  /**
   * Removes a track's resource binding.
   *
   * @param track The SDK video track handle.
   */
  static unregister(
    track: RealtimeVideoTrack
  ): void {
    const originalTrack: RealtimeVideoTrack = RealtimeVideoTrack.resolve(track);
    VideoRenderRegistry.bindings.get(originalTrack)?.dispose();
    VideoRenderRegistry.bindings.delete(originalTrack);
  }

  /**
   * Returns the native rendering library for a track.
   *
   * @param track The SDK video track handle.
   *
   * @returns The native library name, or an empty string without a rendering binding.
   */
  static libraryName(
    track: RealtimeVideoTrack
  ): string {
    return VideoRenderRegistry.bindings.get(RealtimeVideoTrack.resolve(track))?.libraryName ?? '';
  }

  /**
   * Returns the track's camera preview aspect ratio.
   *
   * @param track The SDK video track handle.
   *
   * @returns The preview ratio, or undefined for non-camera tracks or absent configuration.
   */
  static cameraPreviewRatio(
    track: RealtimeVideoTrack
  ): CameraPreviewRatio | undefined {
    return VideoRenderRegistry.bindings.get(RealtimeVideoTrack.resolve(track))?.cameraPreviewRatio();
  }

  /**
   * Updates and broadcasts the preview image; an absent value clears it.
   *
   * @param track The SDK video track handle.
   * @param frame The local preview PixelMap, or undefined to clear the displayed image.
   */
  static setPreviewFrame(
    track: RealtimeVideoTrack,
    frame?: image.PixelMap
  ): void {
    VideoRenderRegistry.bindings.get(RealtimeVideoTrack.resolve(track))?.setPreviewFrame(frame);
  }

  /**
   * Attaches a view and synchronizes preview, readiness, and display settings.
   *
   * @param track The SDK video track handle.
   * @param viewId The native video view identifier.
   * @param contentMode The aspect-fit or aspect-fill content mode.
   * @param previewRatioListener The camera preview ratio handler.
   * @param previewFrameListener The preview image update or clearing handler.
   * @param videoReadyListener The video readiness handler.
   * @param videoFormatListener The track format change handler.
   */
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

  /**
   * Notifies bound views to refresh track format and layout.
   *
   * @param track The SDK video track handle.
   */
  static notifyVideoFormatChanged(
    track: RealtimeVideoTrack
  ): void {
    VideoRenderRegistry.bindings.get(RealtimeVideoTrack.resolve(track))?.notifyVideoFormatChanged();
  }

  /**
   * Updates a view's video content mode.
   *
   * @param track The SDK video track handle.
   * @param viewId The native video view identifier.
   * @param contentMode The aspect-fit or aspect-fill content mode.
   */
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

  /**
   * Detaches a view and stops its rendering notifications.
   *
   * @param track The SDK video track handle.
   * @param viewId The native video view identifier.
   */
  static detach(
    track: RealtimeVideoTrack,
    viewId: string
  ): void {
    VideoRenderRegistry.bindings.get(RealtimeVideoTrack.resolve(track))?.detach(viewId);
  }
}
