import { TrajectoryEffectRendering } from './TrajectoryEffectRendering';
import { TrajectoryId } from './TrajectoryId';
import { TrajectoryPoint } from './TrajectoryPoint';

interface ActiveTrajectory {
  x: number;
  y: number;
  startTime: number;
}

class TrajectoryEffectStyle {
  static readonly TICK_MS: number = 16;
  static readonly INTERPOLATE_STEP: number = 1.5;
  static readonly FADE_STEP: number = 0.05;
  static readonly GLOW_R: number = 0;
  static readonly GLOW_G: number = 255;
  static readonly GLOW_B: number = 100;
  static readonly CORE_WIDTH: number = 3;
  static readonly OUTER_GLOW_WIDTH: number = 18;
  static readonly MID_GLOW_WIDTH: number = 10;
  static readonly HEAD_RADIUS: number = 5;
  static readonly HEAD_GLOW_RADIUS: number = 14;
}

export class DefaultTrajectoryEffectRenderer implements TrajectoryEffectRendering {
  readonly tickIntervalMs: number = TrajectoryEffectStyle.TICK_MS;
  readonly trailContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(
    new RenderingContextSettings(true)
  );
  readonly effectContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(
    new RenderingContextSettings(true)
  );

  // 渲染资源
  private readonly activeTrajectories: Map<number, ActiveTrajectory> = new Map();
  private width: number = 0;
  private height: number = 0;

  // 渲染状态
  private hasTrailPixels: boolean = false;
  private idleFadeTicks: number = 0;

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

  renderBegan(points: TrajectoryPoint[]): void {
    points.forEach((point: TrajectoryPoint): void => {
      this.activeTrajectories.set(point.id.rawValue, {
        x: point.x,
        y: point.y,
        startTime: point.timestamp
      });
    });
  }

  renderMoved(points: TrajectoryPoint[]): void {
    points.forEach((point: TrajectoryPoint): void => {
      const activeTrajectory: ActiveTrajectory | undefined =
        this.activeTrajectories.get(point.id.rawValue);
      if (activeTrajectory === undefined) {
        this.activeTrajectories.set(point.id.rawValue, {
          x: point.x,
          y: point.y,
          startTime: point.timestamp
        });

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

  renderEnded(identifiers: TrajectoryId[]): void {
    identifiers.forEach((identifier: TrajectoryId): void => {
      this.activeTrajectories.delete(identifier.rawValue);
    });
  }

  tick(timestamp: number): void {
    this.fadeTrail();
    this.drawEffects(timestamp);
  }

  isAnimating(): boolean {
    return this.activeTrajectories.size > 0 || this.hasTrailPixels;
  }

  reset(): void {
    this.activeTrajectories.clear();
    this.hasTrailPixels = false;
    this.idleFadeTicks = 0;

    if (this.width > 0 && this.height > 0) {
      this.trailContext.clearRect(0, 0, this.width, this.height);
      this.effectContext.clearRect(0, 0, this.width, this.height);
    }
  }

  private glowColor(alpha: number): string {
    return `rgba(${TrajectoryEffectStyle.GLOW_R},${TrajectoryEffectStyle.GLOW_G},` +
      `${TrajectoryEffectStyle.GLOW_B},${alpha})`;
  }

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
    context.moveTo(x0, y0);

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
    context.moveTo(x0, y0);
    context.lineTo(x1, y1);
    context.stroke();
    context.restore();

    this.hasTrailPixels = true;
    this.idleFadeTicks = 0;
  }

  private fadeTrail(): void {
    if (!this.hasTrailPixels || this.width <= 0 || this.height <= 0) {
      return;
    }

    const context: CanvasRenderingContext2D = this.trailContext;
    context.save();
    context.globalCompositeOperation = 'destination-out';
    context.fillStyle = `rgba(0,0,0,${TrajectoryEffectStyle.FADE_STEP})`;
    context.fillRect(0, 0, this.width, this.height);
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

  private drawEffects(timestamp: number): void {
    if (this.width <= 0 || this.height <= 0) {
      return;
    }

    const context: CanvasRenderingContext2D = this.effectContext;
    context.clearRect(0, 0, this.width, this.height);
    if (this.activeTrajectories.size === 0) {
      return;
    }

    context.save();
    context.globalCompositeOperation = 'lighter';
    this.activeTrajectories.forEach((trajectory: ActiveTrajectory): void => {
      this.drawRings(context, trajectory, timestamp);
      this.drawParticles(context, trajectory, timestamp);
      this.drawHead(context, trajectory.x, trajectory.y);
    });
    context.restore();
  }

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
    gradient.addColorStop(0, this.glowColor(0.9));
    gradient.addColorStop(0.4, this.glowColor(0.54));
    gradient.addColorStop(1, this.glowColor(0));

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
      gradient.addColorStop(0, this.glowColor(alpha));
      gradient.addColorStop(1, this.glowColor(0));

      context.fillStyle = gradient;
      context.beginPath();
      context.arc(x, y, 6, 0, Math.PI * 2);
      context.fill();
    }
  }
}
