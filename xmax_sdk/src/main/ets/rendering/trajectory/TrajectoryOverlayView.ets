//
//  TrajectoryOverlayView.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
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

/** An active touch's trajectory identity and viewport coordinates. */
interface ActiveTouch {

  // Touch identity and position

  /** The touch identity within the current gesture. */
  identifier: TrajectoryId;

  /** The horizontal coordinate. */
  x: number;

  /** The vertical coordinate. */
  y: number;
}

const INTERACTION_SAMPLE_INTERVAL_MS: number = 30;

/** A touch and trajectory overlay submitting points within visible media to generation. */
@Component
export struct TrajectoryOverlayView {

  // Track, interaction enablement, and content mode

  /** The SDK video track bound to this view. */
  @Prop @Watch('onTrackChanged')
  track?: RealtimeVideoTrack = undefined;

  /** Whether to receive and draw trajectory interactions. */
  @Prop @Watch('onInteractionEnabledChanged')
  isInteractionEnabled: boolean = true;

  /**
   * Continues sampling the last touch after release; your app disables it when the retained result
   * ends.
   */
  @Prop @Watch('onReleaseContinuationChanged')
  continuesInteractionAfterRelease: boolean = false;

  /** The video content mode. */
  @Prop @Watch('onContentModeChanged')
  contentMode: VideoContentMode = VideoContentMode.FILL;

  /** The overall interaction lifecycle, combining multiple fingers. */
  onInteractionChanged?: RealtimeInteractionListener;

  /** The trajectory effect renderer. */
  renderer: TrajectoryEffectRendering = new DefaultTrajectoryEffectRenderer();

  // Active touches and original track identity

  /** The active touches in viewport coordinates. */
  private readonly activeTouches: Map<number, ActiveTouch> = new Map();

  /** The last released touch retained for continued sampling. */
  private releasedTouch: ActiveTouch | undefined = undefined;

  /** The original track identity used to detect binding changes. */
  private currentTrack: RealtimeVideoTrack | undefined;

  // Interaction viewport dimensions

  /** The interaction viewport width, in touch-coordinate units. */
  private viewportWidth: number = 0;

  /** The interaction viewport height, in touch-coordinate units. */
  private viewportHeight: number = 0;

  // Animation and interaction sampling schedules

  /** The timer advancing trajectory effects. */
  private tickTimer: number = -1;

  /** The timer sampling interaction points. */
  private sampleTimer: number = -1;

  /** Caches the original track identity for detecting replacements. */
  aboutToAppear(): void {
    this.currentTrack = this.track === undefined ? undefined : RealtimeVideoTrack.resolve(this.track);
  }

  /** Cancels touch interaction and stops sampling and animation timers. */
  aboutToDisappear(): void {
    this.stopTicking();
    this.cancelInteraction();
  }

  /** Cancels touches and changes bindings only when the underlying track changes. */
  private onTrackChanged(): void {
    const track: RealtimeVideoTrack | undefined = this.track === undefined ? undefined :
      RealtimeVideoTrack.resolve(this.track);
    // An ArkUI @Prop copy is not a track replacement; preserve touches during statistics or remote format updates.
    if (track === this.currentTrack) {
      return;
    }
    this.currentTrack = track;
    this.cancelInteraction();
  }

  /** Cancels touches using the old coordinate baseline after content mode changes. */
  private onContentModeChanged(): void {
    this.cancelInteraction();
  }

  /** Cancels touches and effects when interaction is disabled. */
  private onInteractionEnabledChanged(): void {
    if (!this.isInteractionEnabled) {
      this.cancelInteraction();
    }
  }

  /** Updates sampling of the last released touch when continuation changes. */
  private onReleaseContinuationChanged(): void {
    if (!this.continuesInteractionAfterRelease) {
      this.releasedTouch = undefined;
      if (this.activeTouches.size === 0) {
        this.stopSampling();
      }
    } else if (this.activeTouches.size === 0 && this.releasedTouch !== undefined && this.isInteractionEnabled) {
      // Parent state may arrive through @Prop after release; continue that gesture when enabled.
      this.startSampling();
    }
  }

  /** Clears touches, stops sampling and animation, and resets effects. */
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
   * Notifies your app of overall interaction phases without allowing listener errors to disrupt
   * sampling or cleanup.
   *
   * @param phase The start, end, or cancellation phase of valid touch interaction.
   */
  private notifyInteraction(
    phase: RealtimeInteractionPhase
  ): void {
    try {
      this.onInteractionChanged?.(phase);
    } catch (error) {
      XmaxLogger.error(
        'Interaction listener failed: ' + String(error),
        'Interaction'
      );
    }
  }

  /** Starts redraw timing while trajectory effects exist. */
  private startTicking(): void {
    if (this.tickTimer >= 0) {
      return;
    }

    this.tickTimer = setInterval(
      (): void => {
      this.renderer.tick(Date.now());
      if (this.activeTouches.size === 0 && !this.renderer.isAnimating()) {
        this.stopTicking();
      }
    },
      this.renderer.tickIntervalMs
    );
  }

  /** Stops trajectory redraw timing. */
  private stopTicking(): void {
    if (this.tickTimer < 0) {
      return;
    }

    clearInterval(this.tickTimer);
    this.tickTimer = -1;
  }

  /** Submits active points at the interaction sampling interval. */
  private startSampling(): void {
    if (this.sampleTimer >= 0) {
      return;
    }

    this.submitInteraction();
    this.sampleTimer = setInterval(
      (): void => {
      if (!this.isInteractionEnabled) {
        this.stopSampling();
        return;
      }

      this.submitInteraction();
    },
      INTERACTION_SAMPLE_INTERVAL_MS
    );
  }

  /** Stops interaction sampling timing. */
  private stopSampling(): void {
    if (this.sampleTimer < 0) {
      return;
    }

    clearInterval(this.sampleTimer);
    this.sampleTimer = -1;
  }

  /** Submits valid touches only when the track has an interaction binding. */
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
      points.push(new InteractionPoint(
        touch.x,
        touch.y
      ));
    });
    if (points.length === 0 && this.continuesInteractionAfterRelease && this.releasedTouch !== undefined) {
      points.push(new InteractionPoint(
        this.releasedTouch.x,
        this.releasedTouch.y
      ));
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
   * Converts active touches into rendering and interaction samples.
   *
   * @param touch The active touch identity and position.
   * @param timestamp The sampling or animation timestamp, in milliseconds.
   *
   * @returns The trajectory point with viewport coordinates, normalized coordinates, and time.
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
   * Returns the track's visible media rectangle in the viewport.
   *
   * @returns The media rectangle, or null for an invalid track or dimensions.
   */
  private displayedMediaFrame(): InteractionMediaFrame | null {
    const track: RealtimeVideoTrack | undefined = this.track;
    const binding: TrajectoryBinding | null = track === undefined ? null : TrajectoryRegistry.binding(track);
    return binding === null ? null : InteractionCoordinateMapper.displayedFrame(
      this.viewportWidth,
      this.viewportHeight,
      binding.resolvedMediaSize,
      this.contentMode
    );
  }

  /**
   * Clamps a touch's horizontal coordinate to visible media bounds.
   *
   * @param value The horizontal touch coordinate, in viewport units.
   *
   * @returns The clamped viewport horizontal coordinate.
   */
  private clampX(
    value: number
  ): number {
    const frame: InteractionMediaFrame | null = this.displayedMediaFrame();
    const minimum: number = frame === null ? 0 : Math.max(0, frame.x);
    const maximum: number = frame === null ? this.viewportWidth : Math.min(this.viewportWidth, frame.x + frame.width);
    return Math.max(minimum, Math.min(maximum, value));
  }

  /**
   * Clamps a touch's vertical coordinate to visible media bounds.
   *
   * @param value The vertical touch coordinate, in viewport units.
   *
   * @returns The clamped viewport vertical coordinate.
   */
  private clampY(
    value: number
  ): number {
    const frame: InteractionMediaFrame | null = this.displayedMediaFrame();
    const minimum: number = frame === null ? 0 : Math.max(0, frame.y);
    const maximum: number = frame === null ? this.viewportHeight : Math.min(this.viewportHeight, frame.y + frame.height);
    return Math.max(minimum, Math.min(maximum, value));
  }

  /**
   * Starts a touch within visible media and begins drawing and sampling.
   *
   * @param touchObject One touch from a platform event.
   */
  private beginTouch(
    touchObject: TouchObject
  ): void {
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
    this.activeTouches.set(
      touchObject.id,
      touch
    );
    if (wasEmpty) {
      this.notifyInteraction('began');
    }
    this.renderer.renderBegan([
      this.trajectoryPoint(
        touch,
        timestamp
      )
    ]);
    this.startTicking();
    this.startSampling();
  }

  /**
   * Updates an active touch and appends movement to its renderer.
   *
   * @param touchObject One touch from a platform event.
   */
  private moveTouch(
    touchObject: TouchObject
  ): void {
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
      this.trajectoryPoint(
        activeTouch,
        Date.now()
      )
    ]);
  }

  /**
   * Ends drawing and optionally continues the last point; lifecycle notification still occurs on
   * actual release.
   *
   * @param touchObject One touch from a platform event.
   */
  private endTouch(
    touchObject: TouchObject
  ): void {
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
   * Dispatches touch start, move, end, and cancellation events.
   *
   * @param event The touch event to handle.
   */
  private handleTouch(
    event: TouchEvent
  ): void {
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
   * Updates viewport and trajectory canvas dimensions.
   *
   * @param area The component's current layout area.
   */
  private updateArea(
    area: Area
  ): void {
    const width: number = Number(area.width);
    const height: number = Number(area.height);
    if (width <= 0 || height <= 0 ||
      (this.viewportWidth === width && this.viewportHeight === height)) {
      return;
    }

    this.viewportWidth = width;
    this.viewportHeight = height;
    this.cancelInteraction();
    this.renderer.resize(
      width,
      height
    );
  }

  /** Builds the video or interaction component tree. */
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
