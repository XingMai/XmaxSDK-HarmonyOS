//
//  DefaultTrajectoryEffectRenderer.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { TrajectoryEffectRendering } from './TrajectoryEffectRendering';
import { TrajectoryId } from './TrajectoryId';
import { TrajectoryPoint } from './TrajectoryPoint';

/** An active touch location and start time used for trajectory animation. */
interface ActiveTrajectory {

  // Touch location and animation start

  /** The horizontal coordinate. */
  x: number;

  /** The vertical coordinate. */
  y: number;

  /** The touch's animation origin, in milliseconds. */
  startTime: number;
}

/** The default trajectory colors, widths, glow, and decay timing. */
class TrajectoryEffectStyle {

  // Trajectory sampling and decay timing

  /** The trajectory animation refresh interval, in milliseconds. */
  static readonly TICK_MS: number = 16;

  /** The spacing between interpolated trajectory samples. */
  static readonly INTERPOLATE_STEP: number = 1.5;

  /** The opacity decay applied at each trajectory refresh. */
  static readonly FADE_STEP: number = 0.05;

  // Green trajectory colors

  /** The red component of the trajectory glow color. */
  static readonly GLOW_R: number = 0;

  /** The green component of the trajectory glow color. */
  static readonly GLOW_G: number = 255;

  /** The blue component of the trajectory glow color. */
  static readonly GLOW_B: number = 100;

  // Trajectory widths and glow radii

  /** The width of the central trajectory stroke. */
  static readonly CORE_WIDTH: number = 3;

  /** The width of the outer trajectory glow. */
  static readonly OUTER_GLOW_WIDTH: number = 18;

  /** The width of the middle trajectory glow. */
  static readonly MID_GLOW_WIDTH: number = 10;

  /** The radius of the touch head. */
  static readonly HEAD_RADIUS: number = 5;

  /** The radius of the touch head glow. */
  static readonly HEAD_GLOW_RADIUS: number = 14;
}

/** Renders glowing green trajectories, touch halos, and particles that fade after touch completion. */
export class DefaultTrajectoryEffectRenderer implements TrajectoryEffectRendering {

  // Refresh interval and two drawing contexts

  /** The animation refresh interval, in milliseconds. */
  readonly tickIntervalMs: number = TrajectoryEffectStyle.TICK_MS;

  /** The canvas containing retained trajectory strokes. */
  readonly trailContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(
    new RenderingContextSettings(true)
  );

  /** The canvas for animated touch effects. */
  readonly effectContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(
    new RenderingContextSettings(true)
  );

  // Active touch records

  /** The active touch trajectories and their animation origins. */
  private readonly activeTrajectories: Map<number, ActiveTrajectory> = new Map();

  // Drawing area dimensions

  /** The drawing area width. */
  private width: number = 0;

  /** The drawing area height. */
  private height: number = 0;

  // Retained trajectory and decay state

  /** Whether retained trajectory strokes remain on the canvas. */
  private hasTrailPixels: boolean = false;

  /** The remaining idle refreshes used to fade residual strokes. */
  private idleFadeTicks: number = 0;

  /**
   * Updates rendering area dimensions.
   *
   * @param width The rendering area width.
   * @param height The rendering area height.
   */
  resize(
    width: number,
    height: number
  ): void {
    if (width <= 0 || height <= 0 ||
      (this.width === width && this.height === height)) {
      return;
    }

    this.width = width;
    this.height = height;
    this.reset();
  }

  /**
   * Renders new trajectory points.
   *
   * @param points The starting trajectory points.
   */
  renderBegan(
    points: TrajectoryPoint[]
  ): void {
    points.forEach((point: TrajectoryPoint): void => {
      this.activeTrajectories.set(
        point.id.rawValue,
        {
          x: point.x,
          y: point.y,
          startTime: point.timestamp
        }
      );
    });
  }

  /**
   * Renders moving trajectory points.
   *
   * @param points The moved trajectory points.
   */
  renderMoved(
    points: TrajectoryPoint[]
  ): void {
    points.forEach((point: TrajectoryPoint): void => {
      const activeTrajectory: ActiveTrajectory | undefined =
        this.activeTrajectories.get(point.id.rawValue);
      if (activeTrajectory === undefined) {
        this.activeTrajectories.set(
          point.id.rawValue,
          {
            x: point.x,
            y: point.y,
            startTime: point.timestamp
          }
        );

        return;
      }

      this.drawTrail(
        activeTrajectory.x,
        activeTrajectory.y,
        point.x,
        point.y
      );
      activeTrajectory.x = point.x;
      activeTrajectory.y = point.y;
    });
  }

  /**
   * Ends the specified trajectories.
   *
   * @param identifiers The completed trajectory identifiers.
   */
  renderEnded(
    identifiers: TrajectoryId[]
  ): void {
    identifiers.forEach((identifier: TrajectoryId): void => {
      this.activeTrajectories.delete(identifier.rawValue);
    });
  }

  /**
   * Advances one animation frame.
   *
   * @param timestamp The current timestamp, in milliseconds.
   */
  tick(
    timestamp: number
  ): void {
    this.fadeTrail();
    this.drawEffects(timestamp);
  }

  /**
   * Returns whether trajectory effects need continued refreshing.
   *
   * @returns True while active touches or residual trajectories need animation.
   */
  isAnimating(): boolean {
    return this.activeTrajectories.size > 0 || this.hasTrailPixels;
  }

  /** Clears all trajectory effects. */
  reset(): void {
    this.activeTrajectories.clear();
    this.hasTrailPixels = false;
    this.idleFadeTicks = 0;

    if (this.width > 0 && this.height > 0) {
      this.trailContext.clearRect(
        0,
        0,
        this.width,
        this.height
      );
      this.effectContext.clearRect(
        0,
        0,
        this.width,
        this.height
      );
    }
  }

  /**
   * Returns the default green glow color at an opacity.
   *
   * @param alpha The opacity in 0 to 1.
   *
   * @returns The RGBA color string for the canvas.
   */
  private glowColor(
    alpha: number
  ): string {
    return `rgba(${TrajectoryEffectStyle.GLOW_R},${TrajectoryEffectStyle.GLOW_G},` +
      `${TrajectoryEffectStyle.GLOW_B},${alpha})`;
  }

  /**
   * Draws a trajectory layer with width, blur, and opacity.
   *
   * @param x0 The segment start horizontal coordinate.
   * @param y0 The segment start vertical coordinate.
   * @param x1 The segment end horizontal coordinate.
   * @param y1 The segment end vertical coordinate.
   * @param width The frame width, in pixels.
   * @param blur The stroke blur radius.
   * @param alpha The opacity in 0 to 1.
   */
  private strokeLayer(
    x0: number,
    y0: number,
    x1: number,
    y1: number,
    width: number,
    blur: number,
    alpha: number
  ): void {
    const context: CanvasRenderingContext2D = this.trailContext;
    context.lineWidth = width;
    context.shadowBlur = blur;
    context.shadowColor = this.glowColor(alpha);
    context.strokeStyle = this.glowColor(alpha);
    context.beginPath();
    context.moveTo(
      x0,
      y0
    );

    const dx: number = x1 - x0;
    const dy: number = y1 - y0;
    const distance: number = Math.sqrt(dx * dx + dy * dy);
    const steps: number = Math.max(
      1,
      Math.ceil(distance / TrajectoryEffectStyle.INTERPOLATE_STEP)
    );
    for (let index: number = 1; index <= steps; index++) {
      const progress: number = index / steps;
      context.lineTo(
        x0 + dx * progress,
        y0 + dy * progress
      );
    }

    context.stroke();
  }

  /**
   * Draws a trajectory segment with layered glowing strokes.
   *
   * @param x0 The segment start horizontal coordinate.
   * @param y0 The segment start vertical coordinate.
   * @param x1 The segment end horizontal coordinate.
   * @param y1 The segment end vertical coordinate.
   */
  private drawTrail(
    x0: number,
    y0: number,
    x1: number,
    y1: number
  ): void {
    const dx: number = x1 - x0;
    const dy: number = y1 - y0;
    if (dx * dx + dy * dy < 0.25 || this.width <= 0 || this.height <= 0) {
      return;
    }

    const context: CanvasRenderingContext2D = this.trailContext;
    context.save();
    context.globalCompositeOperation = 'lighter';
    context.lineJoin = 'round';
    context.lineCap = 'round';
    this.strokeLayer(
      x0,
      y0,
      x1,
      y1,
      TrajectoryEffectStyle.OUTER_GLOW_WIDTH,
      12,
      0.35
    );
    this.strokeLayer(
      x0,
      y0,
      x1,
      y1,
      TrajectoryEffectStyle.MID_GLOW_WIDTH,
      6,
      0.75
    );
    context.shadowBlur = 0;
    context.shadowColor = 'transparent';
    context.lineWidth = TrajectoryEffectStyle.CORE_WIDTH;
    context.strokeStyle = 'rgba(255,255,255,1)';
    context.beginPath();
    context.moveTo(
      x0,
      y0
    );
    context.lineTo(
      x1,
      y1
    );
    context.stroke();
    context.restore();

    this.hasTrailPixels = true;
    this.idleFadeTicks = 0;
  }

  /** Fades the trajectory canvas so completed paths decay naturally. */
  private fadeTrail(): void {
    if (!this.hasTrailPixels || this.width <= 0 || this.height <= 0) {
      return;
    }

    const context: CanvasRenderingContext2D = this.trailContext;
    context.save();
    context.globalCompositeOperation = 'destination-out';
    context.fillStyle = `rgba(0,0,0,${TrajectoryEffectStyle.FADE_STEP})`;
    context.fillRect(
      0,
      0,
      this.width,
      this.height
    );
    context.restore();

    if (this.activeTrajectories.size > 0) {
      this.idleFadeTicks = 0;
      return;
    }

    this.idleFadeTicks++;
    if (this.idleFadeTicks > 64) {
      this.hasTrailPixels = false;
      this.idleFadeTicks = 0;
    }
  }

  /**
   * Clears the effect layer and draws active touch halos, rings, and particles.
   *
   * @param timestamp The sampling or animation timestamp, in milliseconds.
   */
  private drawEffects(
    timestamp: number
  ): void {
    if (this.width <= 0 || this.height <= 0) {
      return;
    }

    const context: CanvasRenderingContext2D = this.effectContext;
    context.clearRect(
      0,
      0,
      this.width,
      this.height
    );
    if (this.activeTrajectories.size === 0) {
      return;
    }

    context.save();
    context.globalCompositeOperation = 'lighter';
    this.activeTrajectories.forEach((trajectory: ActiveTrajectory): void => {
      this.drawRings(
        context,
        trajectory,
        timestamp
      );
      this.drawParticles(
        context,
        trajectory,
        timestamp
      );
      this.drawHead(
        context,
        trajectory.x,
        trajectory.y
      );
    });
    context.restore();
  }

  /**
   * Draws a touch center and surrounding glow.
   *
   * @param context The drawing canvas context.
   * @param x The horizontal coordinate.
   * @param y The vertical coordinate.
   */
  private drawHead(
    context: CanvasRenderingContext2D,
    x: number,
    y: number
  ): void {
    const gradient: CanvasGradient = context.createRadialGradient(
      x,
      y,
      0,
      x,
      y,
      TrajectoryEffectStyle.HEAD_GLOW_RADIUS
    );
    gradient.addColorStop(
      0,
      this.glowColor(0.9)
    );
    gradient.addColorStop(
      0.4,
      this.glowColor(0.54)
    );
    gradient.addColorStop(
      1,
      this.glowColor(0)
    );

    context.fillStyle = gradient;
    context.beginPath();
    context.arc(
      x,
      y,
      TrajectoryEffectStyle.HEAD_GLOW_RADIUS,
      0,
      Math.PI * 2
    );
    context.fill();

    context.fillStyle = 'rgba(255,255,255,1)';
    context.beginPath();
    context.arc(
      x,
      y,
      TrajectoryEffectStyle.HEAD_RADIUS,
      0,
      Math.PI * 2
    );
    context.fill();
  }

  /**
   * Draws expanding rings based on touch duration.
   *
   * @param context The drawing canvas context.
   * @param trajectory The active trajectory to draw.
   * @param timestamp The sampling or animation timestamp, in milliseconds.
   */
  private drawRings(
    context: CanvasRenderingContext2D,
    trajectory: ActiveTrajectory,
    timestamp: number
  ): void {
    const elapsed: number = (timestamp - trajectory.startTime) / 1000;
    context.lineWidth = 2;

    for (let index: number = 0; index < 2; index++) {
      const pulse: number =
        (Math.sin((elapsed * 1.2 + index * 0.5) * Math.PI * 2) + 1) / 2;
      const radius: number = 10 + index * 14 + pulse * 6;
      context.strokeStyle = this.glowColor(
        0.6 * (1 - index * 0.2) * (0.5 + pulse * 0.5)
      );
      context.beginPath();
      context.arc(
        trajectory.x,
        trajectory.y,
        radius,
        0,
        Math.PI * 2
      );
      context.stroke();
    }
  }

  /**
   * Draws surrounding particles based on touch duration.
   *
   * @param context The drawing canvas context.
   * @param trajectory The active trajectory to draw.
   * @param timestamp The sampling or animation timestamp, in milliseconds.
   */
  private drawParticles(
    context: CanvasRenderingContext2D,
    trajectory: ActiveTrajectory,
    timestamp: number
  ): void {
    const elapsed: number = (timestamp - trajectory.startTime) / 1000;

    for (let index: number = 0; index < 4; index++) {
      const baseAngle: number = index / 4 * Math.PI * 2;
      const direction: number = index % 2 === 0 ? 1 : -1;
      const angle: number = baseAngle + elapsed * 0.06 * direction;
      const x: number = trajectory.x + Math.cos(angle) * 22;
      const y: number = trajectory.y + Math.sin(angle) * 22;
      const alpha: number = 0.6 * (0.6 + Math.sin(elapsed * 3 + index) * 0.4);
      const gradient: CanvasGradient = context.createRadialGradient(
        x,
        y,
        0,
        x,
        y,
        6
      );
      gradient.addColorStop(
        0,
        this.glowColor(alpha)
      );
      gradient.addColorStop(
        1,
        this.glowColor(0)
      );

      context.fillStyle = gradient;
      context.beginPath();
      context.arc(
        x,
        y,
        6,
        0,
        Math.PI * 2
      );
      context.fill();
    }
  }
}
