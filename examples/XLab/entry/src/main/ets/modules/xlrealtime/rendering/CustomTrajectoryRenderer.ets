import {
  TrajectoryEffectRendering,
  TrajectoryId,
  TrajectoryPoint
} from '@xmax/sdk';

interface ActiveTrajectory {
  x: number;
  y: number;
  startTime: number;
}

class CustomTrajectoryStyle {
  static readonly TICK_INTERVAL_MS: number = 16;
  static readonly FADE_STEP: number = 0.08;
  static readonly OUTER_WIDTH: number = 20;
  static readonly MIDDLE_WIDTH: number = 9;
  static readonly CORE_WIDTH: number = 3;
  static readonly HEAD_RADIUS: number = 6;
}

export class CustomTrajectoryRenderer implements TrajectoryEffectRendering {
  readonly tickIntervalMs: number = CustomTrajectoryStyle.TICK_INTERVAL_MS;
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
  private hasTrail: boolean = false;
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
      const trajectory: ActiveTrajectory | undefined =
        this.activeTrajectories.get(point.id.rawValue);
      if (trajectory === undefined) {
        this.activeTrajectories.set(point.id.rawValue, {
          x: point.x,
          y: point.y,
          startTime: point.timestamp
        });

        return;
      }

      this.drawSegment(
        trajectory.x,
        trajectory.y,
        point.x,
        point.y
      );
      trajectory.x = point.x;
      trajectory.y = point.y;
    });
  }

  renderEnded(identifiers: TrajectoryId[]): void {
    identifiers.forEach((identifier: TrajectoryId): void => {
      this.activeTrajectories.delete(identifier.rawValue);
    });
  }

  tick(timestamp: number): void {
    this.fadeTrail();
    this.drawActiveEffects(timestamp);
  }

  isAnimating(): boolean {
    return this.activeTrajectories.size > 0 || this.hasTrail;
  }

  reset(): void {
    this.activeTrajectories.clear();
    this.hasTrail = false;
    this.idleFadeTicks = 0;

    if (this.width > 0 && this.height > 0) {
      this.trailContext.clearRect(0, 0, this.width, this.height);
      this.effectContext.clearRect(0, 0, this.width, this.height);
    }
  }

  private drawSegment(
    x0: number,
    y0: number,
    x1: number,
    y1: number
  ): void {
    if (this.width <= 0 || this.height <= 0) {
      return;
    }

    const context: CanvasRenderingContext2D = this.trailContext;
    context.save();
    context.globalCompositeOperation = 'lighter';
    context.lineCap = 'round';
    context.lineJoin = 'round';

    this.stroke(
      context,
      x0,
      y0,
      x1,
      y1,
      CustomTrajectoryStyle.OUTER_WIDTH,
      'rgba(255,63,205,0.24)'
    );
    this.stroke(
      context,
      x0,
      y0,
      x1,
      y1,
      CustomTrajectoryStyle.MIDDLE_WIDTH,
      'rgba(93,242,255,0.72)'
    );
    this.stroke(
      context,
      x0,
      y0,
      x1,
      y1,
      CustomTrajectoryStyle.CORE_WIDTH,
      'rgba(255,255,255,1)'
    );
    context.restore();

    this.hasTrail = true;
    this.idleFadeTicks = 0;
  }

  private stroke(
    context: CanvasRenderingContext2D,
    x0: number,
    y0: number,
    x1: number,
    y1: number,
    width: number,
    color: string
  ): void {
    context.lineWidth = width;
    context.strokeStyle = color;
    context.beginPath();
    context.moveTo(x0, y0);
    context.lineTo(x1, y1);
    context.stroke();
  }

  private fadeTrail(): void {
    if (!this.hasTrail || this.width <= 0 || this.height <= 0) {
      return;
    }

    const context: CanvasRenderingContext2D = this.trailContext;
    context.save();
    context.globalCompositeOperation = 'destination-out';
    context.fillStyle = `rgba(0,0,0,${CustomTrajectoryStyle.FADE_STEP})`;
    context.fillRect(0, 0, this.width, this.height);
    context.restore();

    if (this.activeTrajectories.size > 0) {
      this.idleFadeTicks = 0;
      return;
    }

    this.idleFadeTicks++;
    if (this.idleFadeTicks > 48) {
      this.hasTrail = false;
      this.idleFadeTicks = 0;
    }
  }

  private drawActiveEffects(timestamp: number): void {
    const context: CanvasRenderingContext2D = this.effectContext;
    context.clearRect(0, 0, this.width, this.height);
    if (this.activeTrajectories.size === 0) {
      return;
    }

    this.activeTrajectories.forEach((trajectory: ActiveTrajectory): void => {
      const elapsed: number = (timestamp - trajectory.startTime) / 1000;
      const pulse: number = (Math.sin(elapsed * Math.PI * 3) + 1) / 2;

      context.strokeStyle = `rgba(255,79,203,${0.35 + pulse * 0.4})`;
      context.lineWidth = 2;
      context.beginPath();
      context.arc(
        trajectory.x,
        trajectory.y,
        12 + pulse * 12,
        0,
        Math.PI * 2
      );
      context.stroke();

      context.fillStyle = 'rgba(93,242,255,1)';
      context.beginPath();
      context.arc(
        trajectory.x,
        trajectory.y,
        CustomTrajectoryStyle.HEAD_RADIUS,
        0,
        Math.PI * 2
      );
      context.fill();
    });
  }
}
