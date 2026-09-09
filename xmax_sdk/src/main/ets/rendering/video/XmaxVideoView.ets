import { image } from '@kit.ImageKit';
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

/** 显示本地或远端实时视频轨道。 */
@Component
export struct XmaxVideoView {
  @Prop @Watch('onTrackChanged')
  track?: RealtimeVideoTrack = undefined;

  /** @internal 远端画面显示状态，供组合视频组件使用。 */
  onVideoReadyChanged?: VideoReadyListener;

  /** 视频内容显示模式。 */
  @Prop @Watch('onContentModeChanged')
  contentMode: VideoContentMode = VideoContentMode.FILL;

  /** 是否开启远端视频的轨迹交互。 */
  @Prop
  isInteractionEnabled: boolean = true;

  /** 轨迹效果渲染器。 */
  trajectoryRenderer: TrajectoryEffectRendering =
    new DefaultTrajectoryEffectRenderer();

  // 渲染资源
  @State private viewId: string = `xmax_video_view_${nextVideoViewId++}`;
  private currentTrack?: RealtimeVideoTrack;
  private attachedTrack?: RealtimeVideoTrack;
  private attachedViewId: string = '';

  // 容器尺寸
  @State private containerWidth: number = 0;
  @State private containerHeight: number = 0;

  // 预览配置
  @State private cameraPreviewRatio: CameraPreviewRatio = CameraPreviewRatio.FILL;
  @State private previewFrame: image.PixelMap | undefined = undefined;
  @State private videoFormat: RealtimeVideoFormat | undefined = undefined;

  aboutToAppear(): void {
    this.currentTrack = this.track === undefined ? undefined : RealtimeVideoTrack.resolve(this.track);
    this.updatePreviewRatio();
  }

  aboutToDisappear(): void {
    this.detachVideo();
  }

  private onTrackChanged(): void {
    const track: RealtimeVideoTrack | undefined = this.track === undefined ?
      undefined : RealtimeVideoTrack.resolve(this.track);
    if (track === this.currentTrack) {
      return;
    }
    this.detachVideo();
    this.currentTrack = track;
    this.previewFrame = undefined;
    this.updatePreviewRatio();
    // 每个轨道使用新的 Surface，旧 onLoad/onDestroy 不能影响新绑定。
    this.viewId = `xmax_video_view_${nextVideoViewId++}`;
  }

  private updatePreviewRatio(): void {
    this.videoFormat = this.track?.videoFormat;
    this.cameraPreviewRatio = this.track === undefined ? CameraPreviewRatio.FILL :
      VideoRenderRegistry.cameraPreviewRatio(this.track) ?? CameraPreviewRatio.FILL;
  }

  private attachVideo(viewId: string): void {
    if (viewId !== this.viewId || this.track === undefined) {
      return;
    }
    this.detachVideo();
    const track: RealtimeVideoTrack = RealtimeVideoTrack.resolve(this.track);
    this.attachedTrack = track;
    this.attachedViewId = viewId;
    VideoRenderRegistry.attach(track, viewId, this.contentMode,
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
      });
  }

  private detachVideo(): void {
    const track: RealtimeVideoTrack | undefined = this.attachedTrack;
    const viewId: string = this.attachedViewId;
    this.attachedTrack = undefined;
    this.attachedViewId = '';
    if (track !== undefined) {
      VideoRenderRegistry.detach(track, viewId);
    }
    this.onVideoReadyChanged?.(false);
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      ForEach(this.track === undefined ? [] : [this.viewId], (viewId: string) => {
        XComponent({
          id: viewId,
          type: XComponentType.SURFACE,
          libraryname: this.renderLibraryName()
        })
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
      }, (viewId: string): string => viewId)

      if (this.previewFrame !== undefined) {
        Image(this.previewFrame)
          .width(this.previewWidth())
          .height(this.previewHeight())
          .objectFit(this.previewImageFit())
      }

      if (this.supportsInteraction()) {
        TrajectoryOverlayView({
          track: this.track,
          isInteractionEnabled: this.isInteractionEnabled,
          contentMode: this.contentMode,
          renderer: this.trajectoryRenderer
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

  private renderLibraryName(): string {
    const track: RealtimeVideoTrack | undefined = this.track;
    return track === undefined ? '' : VideoRenderRegistry.libraryName(track);
  }

  private supportsInteraction(): boolean {
    const track: RealtimeVideoTrack | undefined = this.track;
    return track !== undefined && TrajectoryRegistry.binding(track) !== null;
  }

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

  private trackAspectRatio(): number | undefined {
    const videoFormat: RealtimeVideoFormat | undefined = this.videoFormat;
    if (videoFormat === undefined || videoFormat.width <= 0 || videoFormat.height <= 0) {
      return undefined;
    }

    return videoFormat.width / videoFormat.height;
  }

  private onContentModeChanged(): void {
    const track: RealtimeVideoTrack | undefined = this.track;
    if (track !== undefined) {
      VideoRenderRegistry.setContentMode(track, this.viewId, this.contentMode);
    }
  }

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

  private previewImageFit(): ImageFit {
    return this.contentMode === VideoContentMode.FIT ?
      ImageFit.Contain : ImageFit.Cover;
  }

  private layoutLength(length: Length | undefined): number {
    if (typeof length === 'number') {
      return length;
    }
    if (typeof length === 'string') {
      return Number.parseFloat(length);
    }

    return 0;
  }
}
