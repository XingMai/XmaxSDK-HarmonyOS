//
//  XmaxVideoView.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
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

/** 显示本地或远端实时视频轨道。 */
@Component
export struct XmaxVideoView {

  /** 待展示的视频轨道 */
  @Prop @Watch('onTrackChanged')
  track?: RealtimeVideoTrack = undefined;

  /** 画面可见状态通知 */
  /** @internal 远端画面显示状态，供组合视频组件使用。 */
  onVideoReadyChanged?: VideoReadyListener;

  /** 显示与交互配置 */
  /** 视频内容显示模式。 */
  @Prop @Watch('onContentModeChanged')
  contentMode: VideoContentMode = VideoContentMode.FILL;

  /** 是否开启远端视频的轨迹交互。 */
  @Prop
  isInteractionEnabled: boolean = true;

  /** 有效拖拽的整体生命周期通知。 */
  onInteractionChanged?: RealtimeInteractionListener;

  /** 是否显示视频画面；隐藏时保留视频渲染、轨迹绘制和交互绑定。 */
  @Prop isVideoVisible: boolean = true;

  /** 轨迹效果渲染器。 */
  trajectoryRenderer: TrajectoryEffectRendering =
    new DefaultTrajectoryEffectRenderer();

  /** 视图可见性与方向监听 */
  private readonly orientationObserver: VideoOrientationObserver = new VideoOrientationObserver();
  private isVisible: boolean = false;

  /** 原生视图与轨道绑定 */
  @State private viewId: string = `xmax_video_view_${nextVideoViewId++}`;
  private currentTrack?: RealtimeVideoTrack;
  private attachedTrack?: RealtimeVideoTrack;
  private attachedViewId: string = '';

  /** 容器布局尺寸 */
  @State private containerWidth: number = 0;
  @State private containerHeight: number = 0;

  /** 预览比例、图片与视频格式 */
  @State private cameraPreviewRatio: CameraPreviewRatio = CameraPreviewRatio.FILL;
  @State private previewFrame: image.PixelMap | undefined = undefined;
  @State private videoFormat: RealtimeVideoFormat | undefined = undefined;

  /**
   * 建立当前轨道句柄并同步预览比例与方向监听。
   *
   * @returns 无返回值。
   */
  aboutToAppear(): void {
    this.isVisible = true;
    this.currentTrack = this.track === undefined ? undefined : RealtimeVideoTrack.resolve(this.track);
    this.updatePreviewRatio();
    this.observeOrientation();
  }

  /**
   * 停止方向监听并解除原生视频视图绑定。
   *
   * @returns 无返回值。
   */
  aboutToDisappear(): void {
    this.isVisible = false;
    this.orientationObserver.stop();
    this.detachVideo();
  }

  /**
   * 实际轨道变化时解绑旧视图，并为新轨道创建独立渲染标识。
   *
   * @returns 无返回值。
   */
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
    // 每个轨道使用新的 Surface，旧 onLoad/onDestroy 不能影响新绑定。
    this.viewId = `xmax_video_view_${nextVideoViewId++}`;
  }

  /**
   * 为可见视频轨道订阅布局方向变化。
   *
   * @returns 无返回值。
   */
  private observeOrientation(): void {
    this.orientationObserver.stop();
    if (this.isVisible && this.currentTrack !== undefined) {
      const query = this.getUIContext().getMediaQuery().matchMediaSync('(orientation: landscape)');
      this.orientationObserver.start(this.currentTrack, query);
    }
  }

  /**
   * 从当前视频轨道刷新格式与摄像头预览比例。
   *
   * @returns 无返回值。
   */
  private updatePreviewRatio(): void {
    this.videoFormat = this.track?.videoFormat;
    this.cameraPreviewRatio = this.track === undefined ? CameraPreviewRatio.FILL :
      VideoRenderRegistry.cameraPreviewRatio(this.track) ?? CameraPreviewRatio.FILL;
  }

  /**
   * 将当前视频轨道绑定到匹配的原生 Surface。
   *
   * @param viewId 用于原生视频显示的视图标识。
   * @returns 无返回值。
   */
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

  /**
   * 解除当前原生 Surface 绑定并通知画面不可见。
   *
   * @returns 无返回值。
   */
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

  /**
   * 构建视频或交互视图的 ArkUI 组件树。
   *
   * @returns 由 ArkUI 管理的视图声明，无直接返回值。
   */
  build() {
    Stack({ alignContent: Alignment.Center }) {
      ForEach(this.track === undefined ? [] : [this.viewId], (viewId: string) => {
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
      }, (viewId: string): string => viewId)

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
   * 选择当前视频轨道所需的原生渲染库。
   *
   * @returns 原生库名称；没有轨道时返回空字符串。
   */
  private renderLibraryName(): string {
    const track: RealtimeVideoTrack | undefined = this.track;
    return track === undefined ? '' : VideoRenderRegistry.libraryName(track);
  }

  /**
   * 判断当前轨道是否已绑定交互能力。
   *
   * @returns 轨道具有交互绑定时返回 true。
   */
  private supportsInteraction(): boolean {
    const track: RealtimeVideoTrack | undefined = this.track;
    return track !== undefined && TrajectoryRegistry.binding(track) !== null;
  }

  /**
   * 按当前显示模式计算有效交互画面的布局宽度。
   *
   * @returns 交互覆盖层的宽度。
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
   * 按当前显示模式计算有效交互画面的布局高度。
   *
   * @returns 交互覆盖层的高度。
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
   * 计算当前视频轨道的画面宽高比。
   *
   * @returns 有效宽高比；轨道尺寸不可用时返回 undefined。
   */
  private trackAspectRatio(): number | undefined {
    const videoFormat: RealtimeVideoFormat | undefined = this.videoFormat;
    if (videoFormat === undefined || videoFormat.width <= 0 || videoFormat.height <= 0) {
      return undefined;
    }

    return videoFormat.width / videoFormat.height;
  }

  /**
   * 将新的填充模式同步到当前轨道的渲染绑定。
   *
   * @returns 无返回值。
   */
  private onContentModeChanged(): void {
    const track: RealtimeVideoTrack | undefined = this.track;
    if (track !== undefined) {
      VideoRenderRegistry.setContentMode(track, this.viewId, this.contentMode);
    }
  }

  /**
   * 根据容器尺寸和预览比例计算视频显示宽度。
   *
   * @returns 预览宽度；不限制比例时返回 100%。
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
   * 根据容器尺寸和预览比例计算视频显示高度。
   *
   * @returns 预览高度；不限制比例时返回 100%。
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
   * 将摄像头预览比例配置转换为数值宽高比。
   *
   * @returns 目标宽高比；铺满容器时返回 undefined。
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
   * 将视频填充模式映射为预览图片的缩放方式。
   *
   * @returns FIT 使用等比完整显示，其他模式使用等比裁剪。
   */
  private previewImageFit(): ImageFit {
    return this.contentMode === VideoContentMode.FIT ?
      ImageFit.Contain : ImageFit.Cover;
  }

  /**
   * 将 ArkUI 布局长度转换为可计算的数值。
   *
   * @param length 需要处理的布局长度或数据长度。
   * @returns 数值长度；不支持的类型返回 0。
   */
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
