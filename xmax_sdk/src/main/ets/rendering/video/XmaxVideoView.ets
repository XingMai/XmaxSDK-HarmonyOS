//
//  XmaxVideoView.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { RealtimeInteractionListener } from '../../service/realtime/RealtimeInteraction';
import { image } from '@kit.ImageKit';
import { VideoOrientationObserver } from './VideoOrientationObserver';
import { VideoContentMode } from '../../foundation/media/video/VideoContentMode';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import { RealtimeVideoTrack } from '../../service/realtime/RealtimeVideoTrack';
import { DefaultTrajectoryEffectRenderer } from '../trajectory/DefaultTrajectoryEffectRenderer';
import { TrajectoryEffectRendering } from '../trajectory/TrajectoryEffectRendering';
import { TrajectoryOverlayView } from '../trajectory/TrajectoryOverlayView';
import { TrajectoryRegistry } from '../trajectory/TrajectoryRegistry';
import { CameraPreviewRatio } from './CameraPreviewRatio';
import { VideoReadyListener, VideoRenderRegistry } from './VideoRenderRegistry';

let nextVideoViewId: number = 1;
const PREVIEW_TRANSITION_DURATION: number = 300;

/** A view displaying a local or remote realtime video track. */
@Component
export struct XmaxVideoView {

  // Video track to display

  /** The SDK video track bound to this view. */
  @Prop @Watch('onTrackChanged')
  track?: RealtimeVideoTrack = undefined;

  /** @internal The remote display state callback used by combined video components. */
  onVideoReadyChanged?: VideoReadyListener;

  /** The video content mode. */
  @Prop @Watch('onContentModeChanged')
  contentMode: VideoContentMode = VideoContentMode.FILL;

  /** Whether remote trajectory interaction is enabled. */
  @Prop
  isInteractionEnabled: boolean = true;

  /**
   * Whether to keep sending the last point after release; defaults to false and ends when disabled
   * by your app.
   */
  @Prop continuesInteractionAfterRelease: boolean = false;

  /** The overall valid drag lifecycle handler. */
  onInteractionChanged?: RealtimeInteractionListener;

  /**
   * Whether video is visible; hiding preserves rendering, trajectory drawing, and interaction
   * bindings.
   */
  @Prop isVideoVisible: boolean = true;

  /** The trajectory effect renderer. */
  trajectoryRenderer: TrajectoryEffectRendering =
    new DefaultTrajectoryEffectRenderer();

  // View visibility and orientation observation

  /** The observer synchronizing track and window orientation. */
  private readonly orientationObserver: VideoOrientationObserver = new VideoOrientationObserver();

  /** Whether this view is currently visible. */
  private isVisible: boolean = false;

  // Native view and track binding

  /** The current native rendering view identifier. */
  @State private viewId: string = `xmax_video_view_${nextVideoViewId++}`;

  /** The original track identity used to detect binding changes. */
  private currentTrack?: RealtimeVideoTrack;

  /** The track attached to the current native view. */
  private attachedTrack?: RealtimeVideoTrack;

  /** The native view identifier used by the current binding. */
  private attachedViewId: string = '';

  // Container layout dimensions

  /** The measured video container width. */
  @State private containerWidth: number = 0;

  /** The measured video container height. */
  @State private containerHeight: number = 0;

  // Preview ratio, image, and video format

  /** The aspect ratio used to lay out the camera preview. */
  @State private cameraPreviewRatio: CameraPreviewRatio = CameraPreviewRatio.FILL;

  /** The retained preview or frozen result image. */
  @State private previewFrame: image.PixelMap | undefined = undefined;

  /** The current video dimensions, frame rate, and encoding settings. */
  @State private videoFormat: RealtimeVideoFormat | undefined = undefined;

  /** Resolves the current track and synchronizes preview ratio and orientation observation. */
  aboutToAppear(): void {
    this.isVisible = true;
    this.currentTrack = this.track === undefined ? undefined : RealtimeVideoTrack.resolve(this.track);
    this.updatePreviewRatio();
    this.observeOrientation();
  }

  /** Stops orientation observation and detaches the native video view. */
  aboutToDisappear(): void {
    this.isVisible = false;
    this.orientationObserver.stop();
    this.detachVideo();
  }

  /** Detaches the old view on track replacement and creates an independent rendering identity. */
  private onTrackChanged(): void {
    const track: RealtimeVideoTrack | undefined = this.track === undefined ?
      undefined : RealtimeVideoTrack.resolve(this.track);
    if (track === this.currentTrack) {
      return;
    }

    this.detachVideo();
    this.currentTrack = track;
    this.observeOrientation();
    this.previewFrame = undefined;
    this.updatePreviewRatio();

    // Use a fresh Surface per track so old onLoad/onDestroy events cannot affect the new binding.
    this.viewId = `xmax_video_view_${nextVideoViewId++}`;
  }

  /** Observes layout orientation for a visible track. */
  private observeOrientation(): void {
    this.orientationObserver.stop();
    if (this.isVisible && this.currentTrack !== undefined) {
      const query = this.getUIContext().getMediaQuery().matchMediaSync('(orientation: landscape)');
      this.orientationObserver.start(
        this.currentTrack,
        query
      );
    }
  }

  /** Refreshes format and preview aspect ratio from the track. */
  private updatePreviewRatio(): void {
    this.videoFormat = this.track?.videoFormat;
    this.cameraPreviewRatio = this.track === undefined ? CameraPreviewRatio.FILL :
      VideoRenderRegistry.cameraPreviewRatio(this.track) ?? CameraPreviewRatio.FILL;
  }

  /**
   * Binds the current track to its matching native Surface.
   *
   * @param viewId The native video view identifier.
   */
  private attachVideo(
    viewId: string
  ): void {
    if (viewId !== this.viewId || this.track === undefined) {
      return;
    }

    this.detachVideo();
    const track: RealtimeVideoTrack = RealtimeVideoTrack.resolve(this.track);
    this.attachedTrack = track;
    this.attachedViewId = viewId;

    VideoRenderRegistry.attach(
      track,
      viewId,
      this.contentMode,
      (ratio: CameraPreviewRatio): void => {
        if (this.attachedViewId === viewId) {
          this.cameraPreviewRatio = ratio;
        }
      },
      (frame: image.PixelMap | undefined): void => {
        if (this.attachedViewId === viewId) {
          this.previewFrame = frame;
        }
      },
      (ready: boolean): void => {
        if (this.attachedViewId === viewId) {
          this.onVideoReadyChanged?.(ready);
        }
      },
      (): void => {
        if (this.attachedViewId === viewId) {
          this.videoFormat = track.videoFormat;
        }
      }
    );
  }

  /** Detaches the current Surface and reports video as not visible. */
  private detachVideo(): void {
    const track: RealtimeVideoTrack | undefined = this.attachedTrack;
    const viewId: string = this.attachedViewId;

    this.attachedTrack = undefined;
    this.attachedViewId = '';

    if (track !== undefined) {
      VideoRenderRegistry.detach(
        track,
        viewId
      );
    }

    this.onVideoReadyChanged?.(false);
  }

  /** Builds the video or interaction component tree. */
  build() {
    Stack({ alignContent: Alignment.Center }) {
      ForEach(
        this.track === undefined ? [] : [this.viewId],
        (viewId: string) => {
        XComponent({
          id: viewId,
          type: XComponentType.TEXTURE,
          libraryname: this.renderLibraryName()
        })
          .backgroundColor(Color.Transparent)
          .opacity(this.isVideoVisible ? 1 : 0)
          .animation({ duration: 0 })
          .width(this.previewWidth())
          .height(this.previewHeight())
          .clip(true)
          .animation({
            duration: PREVIEW_TRANSITION_DURATION,
            curve: Curve.EaseInOut
          })
          .onLoad((): void => {
            this.attachVideo(viewId);
          })
          .onDestroy((): void => {
            if (this.attachedViewId === viewId) {
              this.detachVideo();
            }
          })
      },
        (viewId: string): string => viewId
      )

      if (this.previewFrame !== undefined && this.isVideoVisible) {
        Image(this.previewFrame)
          .width(this.previewWidth())
          .height(this.previewHeight())
          .objectFit(this.previewImageFit())
      }

      if (this.supportsInteraction()) {
        TrajectoryOverlayView({
          track: this.track,
          isInteractionEnabled: this.isInteractionEnabled,
          continuesInteractionAfterRelease: this.continuesInteractionAfterRelease,
          contentMode: this.contentMode,
          renderer: this.trajectoryRenderer,
          onInteractionChanged: this.onInteractionChanged
        })
          .width(this.trajectoryOverlayWidth())
          .height(this.trajectoryOverlayHeight())
      }
    }
    .width('100%')
    .height('100%')
    .onSizeChange((_oldValue: SizeOptions, newValue: SizeOptions): void => {
      this.containerWidth = this.layoutLength(newValue.width);
      this.containerHeight = this.layoutLength(newValue.height);
    })
  }

  /**
   * Selects the track's native rendering library.
   *
   * @returns The library name, or an empty string without a track.
   */
  private renderLibraryName(): string {
    const track: RealtimeVideoTrack | undefined = this.track;
    return track === undefined ? '' : VideoRenderRegistry.libraryName(track);
  }

  /**
   * Checks whether the track has an interaction binding.
   *
   * @returns True if an interaction binding exists.
   */
  private supportsInteraction(): boolean {
    const track: RealtimeVideoTrack | undefined = this.track;
    return track !== undefined && TrajectoryRegistry.binding(track) !== null;
  }

  /**
   * Resolves interaction overlay width for the content mode.
   *
   * @returns The interaction overlay width.
   */
  private trajectoryOverlayWidth(): Length {
    const aspectRatio: number | undefined = this.trackAspectRatio();
    if (this.contentMode !== VideoContentMode.FIT || aspectRatio === undefined ||
      this.containerWidth <= 0 || this.containerHeight <= 0) {
      return this.previewWidth();
    }

    const containerAspectRatio: number = this.containerWidth / this.containerHeight;
    return containerAspectRatio > aspectRatio ?
      this.containerHeight * aspectRatio : this.containerWidth;
  }

  /**
   * Resolves interaction overlay height for the content mode.
   *
   * @returns The interaction overlay height.
   */
  private trajectoryOverlayHeight(): Length {
    const aspectRatio: number | undefined = this.trackAspectRatio();
    if (this.contentMode !== VideoContentMode.FIT || aspectRatio === undefined ||
      this.containerWidth <= 0 || this.containerHeight <= 0) {
      return this.previewHeight();
    }

    const containerAspectRatio: number = this.containerWidth / this.containerHeight;
    return containerAspectRatio > aspectRatio ?
      this.containerHeight : this.containerWidth / aspectRatio;
  }

  /**
   * Returns the current track's aspect ratio.
   *
   * @returns The valid aspect ratio, or undefined without valid dimensions.
   */
  private trackAspectRatio(): number | undefined {
    const videoFormat: RealtimeVideoFormat | undefined = this.videoFormat;
    if (videoFormat === undefined || videoFormat.width <= 0 || videoFormat.height <= 0) {
      return undefined;
    }

    return videoFormat.width / videoFormat.height;
  }

  /** Updates the track binding's content mode. */
  private onContentModeChanged(): void {
    const track: RealtimeVideoTrack | undefined = this.track;
    if (track !== undefined) {
      VideoRenderRegistry.setContentMode(
        track,
        this.viewId,
        this.contentMode
      );
    }
  }

  /**
   * Resolves video display width from container bounds and preview ratio.
   *
   * @returns The preview width, or 100% without an aspect constraint.
   */
  private previewWidth(): Length {
    const targetAspectRatio: number | undefined = this.previewAspectRatio();
    if (targetAspectRatio === undefined ||
      this.containerWidth <= 0 || this.containerHeight <= 0) {
      return '100%';
    }

    const containerAspectRatio: number = this.containerWidth / this.containerHeight;
    return containerAspectRatio > targetAspectRatio ?
      this.containerHeight * targetAspectRatio : this.containerWidth;
  }

  /**
   * Resolves video display height from container bounds and preview ratio.
   *
   * @returns The preview height, or 100% without an aspect constraint.
   */
  private previewHeight(): Length {
    const targetAspectRatio: number | undefined = this.previewAspectRatio();
    if (targetAspectRatio === undefined ||
      this.containerWidth <= 0 || this.containerHeight <= 0) {
      return '100%';
    }

    const containerAspectRatio: number = this.containerWidth / this.containerHeight;
    return containerAspectRatio > targetAspectRatio ?
      this.containerHeight : this.containerWidth / targetAspectRatio;
  }

  /**
   * Converts camera preview configuration into a numeric aspect ratio.
   *
   * @returns The target aspect ratio, or undefined to fill the container.
   */
  private previewAspectRatio(): number | undefined {
    switch (this.cameraPreviewRatio) {
      case CameraPreviewRatio.RATIO_1_1:
        return 1;
      case CameraPreviewRatio.RATIO_3_4:
        return 3 / 4;
      case CameraPreviewRatio.RATIO_4_3:
        return 4 / 3;
      case CameraPreviewRatio.RATIO_9_16:
        return 9 / 16;
      case CameraPreviewRatio.RATIO_16_9:
        return 16 / 9;
      case CameraPreviewRatio.FILL:
        return undefined;
      default:
        return undefined;
    }
  }

  /**
   * Maps video content mode into preview image fitting.
   *
   * @returns Aspect-fit for FIT; aspect-fill otherwise.
   */
  private previewImageFit(): ImageFit {
    return this.contentMode === VideoContentMode.FIT ?
      ImageFit.Contain : ImageFit.Cover;
  }

  /**
   * Converts an ArkUI layout length into a number.
   *
   * @param length The layout or data length.
   *
   * @returns The numeric length, or zero for unsupported types.
   */
  private layoutLength(
    length: Length | undefined
  ): number {
    if (typeof length === 'number') {
      return length;
    }
    if (typeof length === 'string') {
      return Number.parseFloat(length);
    }

    return 0;
  }
}
