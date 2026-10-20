//
//  TrajectoryOverlayView.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import { RealtimeInteractionPhase, RealtimeInteractionListener } from '../../service/realtime/RealtimeInteraction';
import { InteractionCoordinateMapper, InteractionMediaFrame } from '../../media/interaction/InteractionCoordinateMapper';
import { VideoContentMode } from '../../foundation/media/video/VideoContentMode';
import { InteractionPoint } from '../../media/interaction/InteractionPoint';
import { RealtimeVideoTrack } from '../../service/realtime/RealtimeVideoTrack';
import { DefaultTrajectoryEffectRenderer } from './DefaultTrajectoryEffectRenderer';
import { TrajectoryBinding } from './TrajectoryBinding';
import { TrajectoryEffectRendering } from './TrajectoryEffectRendering';
import { TrajectoryId } from './TrajectoryId';
import { TrajectoryPoint } from './TrajectoryPoint';
import { TrajectoryRegistry } from './TrajectoryRegistry';

/** 保存活动触点的轨迹标识和视口坐标。 */
interface ActiveTouch {

  /** 触点身份与位置 */
  identifier: TrajectoryId;
  x: number;
  y: number;
}

const INTERACTION_SAMPLE_INTERVAL_MS: number = 30;

/** 覆盖在视频上的触摸与轨迹视图，将有效画面内的触点提交给生成任务。 */
@Component
export struct TrajectoryOverlayView {

  /** 轨道、交互开关与显示模式 */
  @Prop @Watch('onTrackChanged')
  track?: RealtimeVideoTrack = undefined;

  /** 是否接收并绘制轨迹交互。 */
  @Prop @Watch('onInteractionEnabledChanged')
  isInteractionEnabled: boolean = true;

  /** 松手后继续采样最后触点；由接入方在画面保留结束时关闭。 */
  @Prop @Watch('onReleaseContinuationChanged')
  continuesInteractionAfterRelease: boolean = false;

  /** 视频内容显示模式。 */
  @Prop @Watch('onContentModeChanged')
  contentMode: VideoContentMode = VideoContentMode.FILL;

  /** 有效交互生命周期；多指交互按整体通知。 */
  onInteractionChanged?: RealtimeInteractionListener;

  /** 轨迹效果绘制依赖 */
  /** 轨迹效果渲染器。 */
  renderer: TrajectoryEffectRendering = new DefaultTrajectoryEffectRenderer();

  /** 活动触点与原始轨道句柄 */
  private readonly activeTouches: Map<number, ActiveTouch> = new Map();
  private releasedTouch: ActiveTouch | undefined = undefined;
  private currentTrack: RealtimeVideoTrack | undefined;

  /** 交互视口尺寸 */
  private viewportWidth: number = 0;
  private viewportHeight: number = 0;

  /** 动画重绘与交互采样调度 */
  private tickTimer: number = -1;
  private sampleTimer: number = -1;

  /**
   * 缓存当前轨道的原始句柄，供后续轨道更新识别。
   *
   * @returns 无返回值。
   */
  aboutToAppear(): void {
    this.currentTrack = this.track === undefined ? undefined : RealtimeVideoTrack.resolve(this.track);
  }

  /**
   * 取消当前触点交互，并停止采样和动画定时器。
   *
   * @returns 无返回值。
   */
  aboutToDisappear(): void {
    this.stopTicking();
    this.cancelInteraction();
  }

  /**
   * 仅在实际轨道变化时取消触点交互并切换绑定。
   *
   * @returns 无返回值。
   */
  private onTrackChanged(): void {
    const track: RealtimeVideoTrack | undefined = this.track === undefined ? undefined :
      RealtimeVideoTrack.resolve(this.track);
    // ArkUI @Prop 副本变化不代表换轨；刷新统计或远端格式时保留正在进行的触摸。
    if (track === this.currentTrack) {
      return;
    }
    this.currentTrack = track;
    this.cancelInteraction();
  }

  /**
   * 显示模式变化时取消旧坐标基准下的触点交互。
   *
   * @returns 无返回值。
   */
  private onContentModeChanged(): void {
    this.cancelInteraction();
  }

  /**
   * 在交互关闭时取消现有触点与轨迹效果。
   *
   * @returns 无返回值。
   */
  private onInteractionEnabledChanged(): void {
    if (!this.isInteractionEnabled) {
      this.cancelInteraction();
    }
  }

  private onReleaseContinuationChanged(): void {
    if (!this.continuesInteractionAfterRelease) {
      this.releasedTouch = undefined;
      if (this.activeTouches.size === 0) {
        this.stopSampling();
      }
    } else if (this.activeTouches.size === 0 && this.releasedTouch !== undefined && this.isInteractionEnabled) {
      // 父视图状态可能在松手事件之后才传到 @Prop，仍接续该次手势。
      this.startSampling();
    }
  }

  /**
   * 清空活动触点、停止采样与动画，并重置轨迹效果。
   *
   * @returns 无返回值。
   */
  private cancelInteraction(): void {
    const wasActive: boolean = this.activeTouches.size > 0 ||
      (this.continuesInteractionAfterRelease && this.releasedTouch !== undefined);
    this.stopSampling();
    this.stopTicking();
    this.activeTouches.clear();
    this.releasedTouch = undefined;
    this.renderer.reset();
    if (wasActive) {
      this.notifyInteraction('cancelled');
    }
  }

  /**
   * 通知接入方有效交互的整体阶段；接入方异常不影响轨迹采样与清理。
   *
   * @param phase 有效触点交互的开始、结束或取消阶段。
   * @returns 无返回值。
   */
  private notifyInteraction(phase: RealtimeInteractionPhase): void {
    try {
      this.onInteractionChanged?.(phase);
    } catch (error) {
      XmaxLogger.error('Interaction listener failed: ' + String(error), 'Interaction');
    }
  }

  /**
   * 在存在轨迹动画时启动定时重绘。
   *
   * @returns 无返回值。
   */
  private startTicking(): void {
    if (this.tickTimer >= 0) {
      return;
    }

    this.tickTimer = setInterval((): void => {
      this.renderer.tick(Date.now());
      if (this.activeTouches.size === 0 && !this.renderer.isAnimating()) {
        this.stopTicking();
      }
    }, this.renderer.tickIntervalMs);
  }

  /**
   * 停止轨迹重绘定时器。
   *
   * @returns 无返回值。
   */
  private stopTicking(): void {
    if (this.tickTimer < 0) {
      return;
    }

    clearInterval(this.tickTimer);
    this.tickTimer = -1;
  }

  /**
   * 按交互采样周期提交当前活动触点。
   *
   * @returns 无返回值。
   */
  private startSampling(): void {
    if (this.sampleTimer >= 0) {
      return;
    }

    this.submitInteraction();
    this.sampleTimer = setInterval((): void => {
      if (!this.isInteractionEnabled) {
        this.stopSampling();
        return;
      }

      this.submitInteraction();
    }, INTERACTION_SAMPLE_INTERVAL_MS);
  }

  /**
   * 停止交互采样定时器。
   *
   * @returns 无返回值。
   */
  private stopSampling(): void {
    if (this.sampleTimer < 0) {
      return;
    }

    clearInterval(this.sampleTimer);
    this.sampleTimer = -1;
  }

  /**
   * 提交当前有效触点；轨道无交互绑定时跳过发送。
   *
   * @returns 无返回值。
   */
  private submitInteraction(): void {
    const track: RealtimeVideoTrack | undefined = this.track;
    if (track === undefined) {
      return;
    }

    const binding: TrajectoryBinding | null = TrajectoryRegistry.binding(track);
    if (binding === null) {
      return;
    }

    const points: InteractionPoint[] = [];
    this.activeTouches.forEach((touch: ActiveTouch): void => {
      points.push(new InteractionPoint(touch.x, touch.y));
    });
    if (points.length === 0 && this.continuesInteractionAfterRelease && this.releasedTouch !== undefined) {
      points.push(new InteractionPoint(this.releasedTouch.x, this.releasedTouch.y));
    }
    if (points.length === 0) {
      return;
    }
    binding.submit(
      points,
      this.viewportWidth,
      this.viewportHeight,
      this.contentMode
    );
  }

  /**
   * 将活动触点转换为绘制与交互所需的轨迹采样点。
   *
   * @param touch 当前活动触点的标识与位置。
   * @param timestamp 轨迹采样或动画更新时间，单位毫秒。
   * @returns 包含视口坐标、归一化坐标和采样时间的轨迹点。
   */
  private trajectoryPoint(
    touch: ActiveTouch,
    timestamp: number
  ): TrajectoryPoint {
    const frame: InteractionMediaFrame | null = this.displayedMediaFrame();
    const normalizedX: number = frame === null ? 0 : (touch.x - frame.x) / frame.width;
    const normalizedY: number = frame === null ? 0 : (touch.y - frame.y) / frame.height;

    return new TrajectoryPoint(
      touch.identifier,
      touch.x,
      touch.y,
      normalizedX,
      normalizedY,
      timestamp
    );
  }

  /**
   * 读取当前轨道在交互视口中的有效媒体矩形。
   *
   * @returns 媒体矩形；轨道或尺寸无效时返回 null。
   */
  private displayedMediaFrame(): InteractionMediaFrame | null {
    const track: RealtimeVideoTrack | undefined = this.track;
    const binding: TrajectoryBinding | null = track === undefined ? null : TrajectoryRegistry.binding(track);
    return binding === null ? null : InteractionCoordinateMapper.displayedFrame(
      this.viewportWidth, this.viewportHeight, binding.resolvedMediaSize, this.contentMode);
  }

  /**
   * 将触点横坐标限制在有效媒体画面范围内。
   *
   * @param value 待校验、转换或保存的数值。
   * @returns 限制后的视口横坐标。
   */
  private clampX(value: number): number {
    const frame: InteractionMediaFrame | null = this.displayedMediaFrame();
    const minimum: number = frame === null ? 0 : Math.max(0, frame.x);
    const maximum: number = frame === null ? this.viewportWidth : Math.min(this.viewportWidth, frame.x + frame.width);
    return Math.max(minimum, Math.min(maximum, value));
  }

  /**
   * 将触点纵坐标限制在有效媒体画面范围内。
   *
   * @param value 待校验、转换或保存的数值。
   * @returns 限制后的视口纵坐标。
   */
  private clampY(value: number): number {
    const frame: InteractionMediaFrame | null = this.displayedMediaFrame();
    const minimum: number = frame === null ? 0 : Math.max(0, frame.y);
    const maximum: number = frame === null ? this.viewportHeight : Math.min(this.viewportHeight, frame.y + frame.height);
    return Math.max(minimum, Math.min(maximum, value));
  }

  /**
   * 在有效画面内建立活动触点，开始轨迹绘制和交互采样。
   *
   * @param touchObject 平台触摸事件中的单个触点。
   * @returns 无返回值。
   */
  private beginTouch(touchObject: TouchObject): void {
    const frame: InteractionMediaFrame | null = this.displayedMediaFrame();
    if (frame === null || touchObject.x < Math.max(0, frame.x) ||
      touchObject.x > Math.min(this.viewportWidth, frame.x + frame.width) ||
      touchObject.y < Math.max(0, frame.y) ||
      touchObject.y > Math.min(this.viewportHeight, frame.y + frame.height)) {
      return;
    }
    const timestamp: number = Date.now();
    const touch: ActiveTouch = {
      identifier: new TrajectoryId(touchObject.id),
      x: this.clampX(touchObject.x),
      y: this.clampY(touchObject.y)
    };
    const wasEmpty: boolean = this.activeTouches.size === 0;
    this.releasedTouch = undefined;
    this.activeTouches.set(touchObject.id, touch);
    if (wasEmpty) {
      this.notifyInteraction('began');
    }
    this.renderer.renderBegan([
      this.trajectoryPoint(touch, timestamp)
    ]);
    this.startTicking();
    this.startSampling();
  }

  /**
   * 更新活动触点位置，并向渲染器追加移动轨迹。
   *
   * @param touchObject 平台触摸事件中的单个触点。
   * @returns 无返回值。
   */
  private moveTouch(touchObject: TouchObject): void {
    const activeTouch: ActiveTouch | undefined =
      this.activeTouches.get(touchObject.id);
    if (activeTouch === undefined) {
      this.beginTouch(touchObject);
      return;
    }

    const x: number = this.clampX(touchObject.x);
    const y: number = this.clampY(touchObject.y);
    const dx: number = x - activeTouch.x;
    const dy: number = y - activeTouch.y;
    if (dx * dx + dy * dy < 0.25) {
      return;
    }

    activeTouch.x = x;
    activeTouch.y = y;
    this.renderer.renderMoved([
      this.trajectoryPoint(activeTouch, Date.now())
    ]);
  }

  /**
   * 结束触点绘制；按配置续发最后触点，生命周期仍在实际松手时通知。
   *
   * @param touchObject 平台触摸事件中的单个触点。
   * @returns 无返回值。
   */
  private endTouch(touchObject: TouchObject): void {
    const activeTouch: ActiveTouch | undefined =
      this.activeTouches.get(touchObject.id);
    if (activeTouch === undefined) {
      return;
    }

    this.activeTouches.delete(touchObject.id);
    this.renderer.renderEnded([activeTouch.identifier]);
    if (this.activeTouches.size === 0) {
      this.releasedTouch = activeTouch;
      if (!this.continuesInteractionAfterRelease) {
        this.stopSampling();
      }
      this.notifyInteraction('ended');
    }
  }

  /**
   * 根据触摸阶段分发触点开始、移动、结束或取消事件。
   *
   * @param event 待处理的触摸事件。
   * @returns 无返回值。
   */
  private handleTouch(event: TouchEvent): void {
    if (!this.isInteractionEnabled) {
      return;
    }

    if (event.type === TouchType.Down) {
      for (let index: number = 0; index < event.changedTouches.length; index++) {
        this.beginTouch(event.changedTouches[index]);
      }
      return;
    }

    if (event.type === TouchType.Move) {
      for (let index: number = 0; index < event.changedTouches.length; index++) {
        this.moveTouch(event.changedTouches[index]);
      }
      return;
    }

    if (event.type === TouchType.Cancel) {
      this.cancelInteraction();
      return;
    }
    if (event.type === TouchType.Up) {
      for (let index: number = 0; index < event.changedTouches.length; index++) {
        this.endTouch(event.changedTouches[index]);
      }
    }
  }

  /**
   * 更新交互视口尺寸并同步轨迹画布大小。
   *
   * @param area 组件当前布局区域。
   * @returns 无返回值。
   */
  private updateArea(area: Area): void {
    const width: number = Number(area.width);
    const height: number = Number(area.height);
    if (width <= 0 || height <= 0 ||
      (this.viewportWidth === width && this.viewportHeight === height)) {
      return;
    }

    this.viewportWidth = width;
    this.viewportHeight = height;
    this.cancelInteraction();
    this.renderer.resize(width, height);
  }

  /**
   * 构建视频或交互视图的 ArkUI 组件树。
   *
   * @returns 由 ArkUI 管理的视图声明，无直接返回值。
   */
  build() {
    Stack() {
      Canvas(this.renderer.trailContext)
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .onAreaChange((_oldArea: Area, newArea: Area): void => {
          this.updateArea(newArea);
        })

      Canvas(this.renderer.effectContext)
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(
      this.isInteractionEnabled ? HitTestMode.Default : HitTestMode.None
    )
    .onTouch((event: TouchEvent): void => {
      this.handleTouch(event);
    })
  }
}
