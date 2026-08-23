import { image } from '@kit.ImageKit';
import { VideoContentMode } from '../../foundation/media/video/VideoContentMode';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import { RealtimeVideoTrack } from '../../service/realtime/RealtimeVideoTrack';
import { DefaultTrajectoryEffectRenderer } from '../trajectory/DefaultTrajectoryEffectRenderer';
import { TrajectoryEffectRendering } from '../trajectory/TrajectoryEffectRendering';
import { TrajectoryOverlayView } from '../trajectory/TrajectoryOverlayView';
import { TrajectoryRegistry } from '../trajectory/TrajectoryRegistry';
import { CameraPreviewRatio } from './CameraPreviewRatio';
import { VideoRenderRegistry } from './VideoRenderRegistry';

let nextVideoViewId: number = 1;
const PREVIEW_TRANSITION_DURATION: number = 300;

/** 显示本地或远端实时视频轨道。 */
@Component
export struct XmaxVideoView {
  track?: RealtimeVideoTrack;

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
  private readonly viewId: string = `xmax_video_view_${nextVideoViewId++}`;

  // 容器尺寸
  @State private containerWidth: number = 0;
  @State private containerHeight: number = 0;

  // 预览配置
  @State private cameraPreviewRatio: CameraPreviewRatio = CameraPreviewRatio.FILL;
  @State private previewFrame: image.PixelMap | undefined = undefined;

  aboutToAppear(): void {
    const track: RealtimeVideoTrack | undefined = this.track;
    if (track === undefined) {
      return;
    }

    const ratio: CameraPreviewRatio | undefined =
      VideoRenderRegistry.cameraPreviewRatio(track);
    if (ratio !== undefined) {
      this.cameraPreviewRatio = ratio;
    }
  }

  aboutToDisappear(): void {
    const track: RealtimeVideoTrack | undefined = this.track;
    if (track !== undefined) {
      VideoRenderRegistry.detach(track, this.viewId);
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      XComponent({
        id: this.viewId,
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
          const track: RealtimeVideoTrack | undefined = this.track;
          if (track === undefined) {
            return;
          }

          VideoRenderRegistry.attach(
            track,
            this.viewId,
            this.contentMode,
            (ratio: CameraPreviewRatio): void => {
              this.cameraPreviewRatio = ratio;
            },
            (frame: image.PixelMap | undefined): void => {
              this.previewFrame = frame;
            }
          );
        })

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
    const videoFormat: RealtimeVideoFormat | undefined = this.track?.videoFormat;
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
