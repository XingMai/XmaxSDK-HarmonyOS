//
//  VideoRenderRegistry.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { image } from '@kit.ImageKit';
import { VideoContentMode } from '../../foundation/media/video/VideoContentMode';
import { RealtimeVideoTrack } from '../../service/realtime/RealtimeVideoTrack';
import { CameraPreviewRatio } from './CameraPreviewRatio';

/**
 * 接收摄像头预览比例更新的回调。
 *
 * @param ratio 摄像头预览的显示比例。
 * @returns 无返回值。
 */
type CameraPreviewRatioListener = (ratio: CameraPreviewRatio) => void;

/**
 * 接收视频画面是否已可见的状态变化。
 *
 * @param ready 视频画面是否已经可见。
 * @returns 无返回值。
 */
export type VideoReadyListener = (ready: boolean) => void;

/**
 * 接收预览图片更新；空值表示清除预览。
 *
 * @param frame 需要处理或交付的媒体帧。
 * @returns 无返回值。
 */
type PreviewFrameListener = (frame: image.PixelMap | undefined) => void;

/**
 * 视频轨道格式变化后通知视图刷新布局。
 *
 * @returns 无返回值。
 */
type VideoFormatListener = () => void;

/** 保存已绑定视图的显示模式及预览、就绪和格式监听器。 */
interface AttachedVideoView {

  /** 视图显示配置 */
  contentMode: VideoContentMode;

  /** 预览、就绪与格式通知 */
  previewRatioListener: CameraPreviewRatioListener;
  previewFrameListener: PreviewFrameListener;
  videoReadyListener?: VideoReadyListener;
  videoFormatListener?: VideoFormatListener;
}

/** 管理一条视频轨道绑定的视图，并广播预览图片和显示状态。 */
export class VideoRenderBinding {

  /** 原生渲染绑定依赖 */
  readonly libraryName: string;
  /**
   * 将指定媒体流绑定到原生视频视图。
   *
   * @param viewId 用于原生视频显示的视图标识。
   * @param contentMode 媒体在视口中的完整显示或裁剪填充方式。
   * @returns 无返回值。
   */
  private readonly attachHandler: (
    viewId: string,
    contentMode: VideoContentMode
  ) => void;
  /**
   * 解除指定原生视频视图的媒体流绑定。
   *
   * @param viewId 用于原生视频显示的视图标识。
   * @returns 无返回值。
   */
  private readonly detachHandler: (viewId: string) => void;

  /** 已绑定视图记录 */
  private readonly attachedViews: Map<string, AttachedVideoView> = new Map();

  /** 共享预览与视频就绪状态 */
  private previewRatio?: CameraPreviewRatio;
  private previewFrame?: image.PixelMap;
  private videoReady: boolean = false;

  /**
   * 创建视频轨道渲染绑定。
   *
   * @param libraryName XComponent 使用的原生渲染库名称。
   * @param attachHandler 将原生视频流绑定到视图的处理函数。
   * @param detachHandler 解除原生视频视图绑定的处理函数。
   * @param previewRatio 摄像头预览使用的目标显示比例。
   * @returns 新建的 VideoRenderBinding 实例。
   */
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

  /**
   * 绑定视频视图并同步预览、就绪状态和显示配置。
   *
   * @param viewId 用于原生视频显示的视图标识。
   * @param contentMode 媒体在视口中的完整显示或裁剪填充方式。
   * @param previewRatioListener 接收摄像头预览比例更新的监听器。
   * @param previewFrameListener 接收预览图更新或清除通知的监听器。
   * @param videoReadyListener 接收视频画面就绪状态的监听器。
   * @param videoFormatListener 轨道视频格式变化时执行的回调。
   * @returns 无返回值。
   */
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

  /**
   * 解绑指定视频视图，停止向其发送渲染状态。
   *
   * @param viewId 渲染容器标识。
   * @returns 无返回值。
   */
  detach(viewId: string): void {
    const view: AttachedVideoView | undefined = this.attachedViews.get(viewId);
    if (view === undefined) {
      return;
    }
    this.attachedViews.delete(viewId);
    view.videoReadyListener?.(false);
    this.detachHandler(viewId);
  }

  /**
   * 更新指定视图的视频填充模式。
   *
   * @param viewId 用于原生视频显示的视图标识。
   * @param contentMode 媒体在视口中的完整显示或裁剪填充方式。
   * @returns 无返回值。
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
    this.attachHandler(viewId, contentMode);
  }

  /**
   * 更新并广播视频画面可见状态。
   *
   * @param ready 视频画面是否已经可见。
   * @returns 无返回值。
   */
  setVideoReady(ready: boolean): void {
    if (this.videoReady === ready) {
      return;
    }
    this.videoReady = ready;
    this.attachedViews.forEach((view: AttachedVideoView): void => {
      view.videoReadyListener?.(ready);
    });
  }

  /**
   * 通知已绑定视图刷新轨道格式和布局。
   *
   * @returns 无返回值。
   */
  notifyVideoFormatChanged(): void {
    this.attachedViews.forEach((view: AttachedVideoView): void => view.videoFormatListener?.());
  }

  /**
   * 解绑全部视图，释放渲染绑定持有的回调。
   *
   * @returns 无返回值。
   */
  dispose(): void {
    this.setPreviewFrame(undefined);
    this.setVideoReady(false);
    this.attachedViews.forEach((_view: AttachedVideoView, viewId: string): void => {
      this.detach(viewId);
    });
  }

  /**
   * 读取轨道指定的摄像头预览比例。
   *
   * @returns 预览比例；非摄像头或未设置时返回 undefined。
   */
  cameraPreviewRatio(): CameraPreviewRatio | undefined {
    return this.previewRatio;
  }

  /**
   * 更新并广播预览图片；空值表示清除。
   *
   * @param frame 需要处理或交付的媒体帧。
   * @returns 无返回值。
   */
  setPreviewFrame(frame?: image.PixelMap): void {
    this.previewFrame = frame;
    this.attachedViews.forEach((attachedView: AttachedVideoView): void => {
      attachedView.previewFrameListener(frame);
    });
  }
}

/** 按视频轨道登记和查找渲染资源，连接媒体控制器与 ArkUI 视频视图。 */
export class VideoRenderRegistry {

  /** 轨道到渲染资源的弱引用绑定 */
  private static readonly bindings: Map<RealtimeVideoTrack, VideoRenderBinding> = new Map();

  /**
   * 将视频轨道与其绑定资源登记到注册表。
   *
   * @param track SDK 返回的视频轨道句柄。
   * @param binding 需要关联到轨道的资源绑定。
   * @returns 无返回值。
   */
  static register(
    track: RealtimeVideoTrack,
    binding: VideoRenderBinding
  ): void {
    VideoRenderRegistry.bindings.set(RealtimeVideoTrack.resolve(track), binding);
  }

  /**
   * 移除指定视频轨道的资源绑定。
   *
   * @param track SDK 返回的视频轨道句柄。
   * @returns 无返回值。
   */
  static unregister(track: RealtimeVideoTrack): void {
    const originalTrack: RealtimeVideoTrack = RealtimeVideoTrack.resolve(track);
    VideoRenderRegistry.bindings.get(originalTrack)?.dispose();
    VideoRenderRegistry.bindings.delete(originalTrack);
  }

  /**
   * 读取视频轨道所需的原生渲染库名称。
   *
   * @param track SDK 返回的视频轨道句柄。
   * @returns 原生库名称；没有渲染绑定时返回空字符串。
   */
  static libraryName(track: RealtimeVideoTrack): string {
    return VideoRenderRegistry.bindings.get(RealtimeVideoTrack.resolve(track))?.libraryName ?? '';
  }

  /**
   * 读取轨道指定的摄像头预览比例。
   *
   * @param track SDK 返回的视频轨道句柄。
   * @returns 预览比例；非摄像头或未设置时返回 undefined。
   */
  static cameraPreviewRatio(track: RealtimeVideoTrack): CameraPreviewRatio | undefined {
    return VideoRenderRegistry.bindings.get(RealtimeVideoTrack.resolve(track))?.cameraPreviewRatio();
  }

  /**
   * 更新并广播预览图片；空值表示清除。
   *
   * @param track SDK 返回的视频轨道句柄。
   * @param frame 需要处理或交付的媒体帧。
   * @returns 无返回值。
   */
  static setPreviewFrame(
    track: RealtimeVideoTrack,
    frame?: image.PixelMap
  ): void {
    VideoRenderRegistry.bindings.get(RealtimeVideoTrack.resolve(track))?.setPreviewFrame(frame);
  }

  /**
   * 绑定视频视图并同步预览、就绪状态和显示配置。
   *
   * @param track SDK 返回的视频轨道句柄。
   * @param viewId 用于原生视频显示的视图标识。
   * @param contentMode 媒体在视口中的完整显示或裁剪填充方式。
   * @param previewRatioListener 接收摄像头预览比例更新的监听器。
   * @param previewFrameListener 接收预览图更新或清除通知的监听器。
   * @param videoReadyListener 接收视频画面就绪状态的监听器。
   * @param videoFormatListener 轨道视频格式变化时执行的回调。
   * @returns 无返回值。
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
   * 通知已绑定视图刷新轨道格式和布局。
   *
   * @param track SDK 返回的视频轨道句柄。
   * @returns 无返回值。
   */
  static notifyVideoFormatChanged(track: RealtimeVideoTrack): void {
    VideoRenderRegistry.bindings.get(RealtimeVideoTrack.resolve(track))?.notifyVideoFormatChanged();
  }

  /**
   * 更新指定视图的视频填充模式。
   *
   * @param track SDK 返回的视频轨道句柄。
   * @param viewId 用于原生视频显示的视图标识。
   * @param contentMode 媒体在视口中的完整显示或裁剪填充方式。
   * @returns 无返回值。
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
   * 解绑指定视频视图，停止向其发送渲染状态。
   *
   * @param track SDK 返回的视频轨道句柄。
   * @param viewId 用于原生视频显示的视图标识。
   * @returns 无返回值。
   */
  static detach(
    track: RealtimeVideoTrack,
    viewId: string
  ): void {
    VideoRenderRegistry.bindings.get(RealtimeVideoTrack.resolve(track))?.detach(viewId);
  }
}
