import { VideoContentMode } from '../../foundation/media/video/VideoContentMode';
import { InteractionPoint } from '../../media/interaction/InteractionPoint';
import { RealtimeVideoTrack } from '../../service/realtime/RealtimeVideoTrack';
import { DefaultTrajectoryEffectRenderer } from './DefaultTrajectoryEffectRenderer';
import { TrajectoryBinding } from './TrajectoryBinding';
import { TrajectoryEffectRendering } from './TrajectoryEffectRendering';
import { TrajectoryId } from './TrajectoryId';
import { TrajectoryPoint } from './TrajectoryPoint';
import { TrajectoryRegistry } from './TrajectoryRegistry';

interface ActiveTouch {
  identifier: TrajectoryId;
  x: number;
  y: number;
}

const INTERACTION_SAMPLE_INTERVAL_MS: number = 30;

@Component
export struct TrajectoryOverlayView {
  track?: RealtimeVideoTrack;

  /** 是否接收并绘制轨迹交互。 */
  @Prop @Watch('onInteractionEnabledChanged')
  isInteractionEnabled: boolean = true;

  /** 视频内容显示模式。 */
  @Prop
  contentMode: VideoContentMode = VideoContentMode.FILL;

  /** 轨迹效果渲染器。 */
  renderer: TrajectoryEffectRendering = new DefaultTrajectoryEffectRenderer();

  // 交互资源
  private readonly activeTouches: Map<number, ActiveTouch> = new Map();
  private viewportWidth: number = 0;
  private viewportHeight: number = 0;

  // 运行状态
  private tickTimer: number = -1;
  private sampleTimer: number = -1;

  aboutToDisappear(): void {
    this.stopTicking();
    this.cancelInteraction();
  }

  private onInteractionEnabledChanged(): void {
    if (!this.isInteractionEnabled) {
      this.cancelInteraction();
    }
  }

  private cancelInteraction(): void {
    this.stopSampling();
    this.stopTicking();
    this.activeTouches.clear();
    this.renderer.reset();
  }

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

  private stopTicking(): void {
    if (this.tickTimer < 0) {
      return;
    }

    clearInterval(this.tickTimer);
    this.tickTimer = -1;
  }

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

  private stopSampling(): void {
    if (this.sampleTimer < 0) {
      return;
    }

    clearInterval(this.sampleTimer);
    this.sampleTimer = -1;
  }

  private submitInteraction(): void {
    const track: RealtimeVideoTrack | undefined = this.track;
    if (track === undefined) {
      return;
    }

    const binding: TrajectoryBinding | null = TrajectoryRegistry.binding(track);
    if (binding === null || this.activeTouches.size === 0) {
      return;
    }

    const points: InteractionPoint[] = [];
    this.activeTouches.forEach((touch: ActiveTouch): void => {
      points.push(new InteractionPoint(touch.x, touch.y));
    });
    binding.submit(
      points,
      this.viewportWidth,
      this.viewportHeight,
      this.contentMode
    );
  }

  private trajectoryPoint(
    touch: ActiveTouch,
    timestamp: number
  ): TrajectoryPoint {
    const normalizedX: number = this.viewportWidth > 0 ?
      touch.x / this.viewportWidth : 0;
    const normalizedY: number = this.viewportHeight > 0 ?
      touch.y / this.viewportHeight : 0;

    return new TrajectoryPoint(
      touch.identifier,
      touch.x,
      touch.y,
      normalizedX,
      normalizedY,
      timestamp
    );
  }

  private clampX(value: number): number {
    return Math.max(0, Math.min(this.viewportWidth, value));
  }

  private clampY(value: number): number {
    return Math.max(0, Math.min(this.viewportHeight, value));
  }

  private beginTouch(touchObject: TouchObject): void {
    const timestamp: number = Date.now();
    const touch: ActiveTouch = {
      identifier: new TrajectoryId(touchObject.id),
      x: this.clampX(touchObject.x),
      y: this.clampY(touchObject.y)
    };
    this.activeTouches.set(touchObject.id, touch);
    this.renderer.renderBegan([
      this.trajectoryPoint(touch, timestamp)
    ]);
    this.startTicking();
    this.startSampling();
  }

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

  private endTouch(touchObject: TouchObject): void {
    const activeTouch: ActiveTouch | undefined =
      this.activeTouches.get(touchObject.id);
    if (activeTouch === undefined) {
      return;
    }

    this.activeTouches.delete(touchObject.id);
    this.renderer.renderEnded([activeTouch.identifier]);
    if (this.activeTouches.size === 0) {
      this.stopSampling();
    }
  }

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

    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      for (let index: number = 0; index < event.changedTouches.length; index++) {
        this.endTouch(event.changedTouches[index]);
      }
    }
  }

  private updateArea(area: Area): void {
    const width: number = Number(area.width);
    const height: number = Number(area.height);
    if (width <= 0 || height <= 0 ||
      (this.viewportWidth === width && this.viewportHeight === height)) {
      return;
    }

    this.viewportWidth = width;
    this.viewportHeight = height;
    this.activeTouches.clear();
    this.stopSampling();
    this.renderer.resize(width, height);
  }

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
