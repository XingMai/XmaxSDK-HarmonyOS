//
//  DefaultTrajectoryEffectRenderer.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { TrajectoryEffectRendering } from './TrajectoryEffectRendering';
import { TrajectoryId } from './TrajectoryId';
import { TrajectoryPoint } from './TrajectoryPoint';

/** 记录单个活动触点的位置与起始时间，供轨迹动画绘制。 */
interface ActiveTrajectory {

  /** 触点位置与动画起点 */
  x: number;
  y: number;
  startTime: number;
}

/** 集中定义默认轨迹的颜色、线宽、光晕和衰减节奏。 */
class TrajectoryEffectStyle {

  /** 轨迹采样与衰减节奏 */
  static readonly TICK_MS: number = 16;
  static readonly INTERPOLATE_STEP: number = 1.5;
  static readonly FADE_STEP: number = 0.05;

  /** 绿色轨迹颜色 */
  static readonly GLOW_R: number = 0;
  static readonly GLOW_G: number = 255;
  static readonly GLOW_B: number = 100;

  /** 轨迹线宽与光晕半径 */
  static readonly CORE_WIDTH: number = 3;
  static readonly OUTER_GLOW_WIDTH: number = 18;
  static readonly MID_GLOW_WIDTH: number = 10;
  static readonly HEAD_RADIUS: number = 5;
  static readonly HEAD_GLOW_RADIUS: number = 14;
}

/** 绘制绿色发光轨迹、触点光晕与粒子，并在触摸结束后逐步消退。 */
export class DefaultTrajectoryEffectRenderer implements TrajectoryEffectRendering {

  /** 刷新节奏与双层绘图上下文 */
  readonly tickIntervalMs: number = TrajectoryEffectStyle.TICK_MS;
  readonly trailContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(
    new RenderingContextSettings(true)
  );
  readonly effectContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(
    new RenderingContextSettings(true)
  );

  /** 活动触点记录 */
  private readonly activeTrajectories: Map<number, ActiveTrajectory> = new Map();

  /** 绘制区域尺寸 */
  private width: number = 0;
  private height: number = 0;

  /** 轨迹残留与消退状态 */
  private hasTrailPixels: boolean = false;
  private idleFadeTicks: number = 0;

  /**
   * 更新渲染区域尺寸。
   *
   * @param width 渲染区域宽度。
   * @param height 渲染区域高度。
   * @returns 无返回值。
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
   * 渲染轨迹起点。
   *
   * @param points 新开始的轨迹点。
   * @returns 无返回值。
   */
  renderBegan(points: TrajectoryPoint[]): void {
    points.forEach((point: TrajectoryPoint): void => {
      this.activeTrajectories.set(point.id.rawValue, {
        x: point.x,
        y: point.y,
        startTime: point.timestamp
      });
    });
  }

  /**
   * 渲染移动中的轨迹点。
   *
   * @param points 发生移动的轨迹点。
   * @returns 无返回值。
   */
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

  /**
   * 结束指定轨迹。
   *
   * @param identifiers 已结束的轨迹标识。
   * @returns 无返回值。
   */
  renderEnded(identifiers: TrajectoryId[]): void {
    identifiers.forEach((identifier: TrajectoryId): void => {
      this.activeTrajectories.delete(identifier.rawValue);
    });
  }

  /**
   * 推进一帧动态轨迹效果。
   *
   * @param timestamp 当前时间戳，单位为毫秒。
   * @returns 无返回值。
   */
  tick(timestamp: number): void {
    this.fadeTrail();
    this.drawEffects(timestamp);
  }

  /**
   * 判断是否仍有需要持续刷新的轨迹效果。
   *
   * @returns 仍有活动触点或残留轨迹需要消退时返回 true。
   */
  isAnimating(): boolean {
    return this.activeTrajectories.size > 0 || this.hasTrailPixels;
  }

  /**
   * 清理全部轨迹效果。
   *
   * @returns 无返回值。
   */
  reset(): void {
    this.activeTrajectories.clear();
    this.hasTrailPixels = false;
    this.idleFadeTicks = 0;

    if (this.width > 0 && this.height > 0) {
      this.trailContext.clearRect(0, 0, this.width, this.height);
      this.effectContext.clearRect(0, 0, this.width, this.height);
    }
  }

  /**
   * 按指定透明度生成默认轨迹的绿色光晕颜色。
   *
   * @param alpha 透明度，范围为 0～1。
   * @returns 可供画布使用的 RGBA 颜色文本。
   */
  private glowColor(alpha: number): string {
    return `rgba(${TrajectoryEffectStyle.GLOW_R},${TrajectoryEffectStyle.GLOW_G},` +
      `${TrajectoryEffectStyle.GLOW_B},${alpha})`;
  }

  /**
   * 绘制一层指定线宽、模糊半径和透明度的轨迹线段。
   *
   * @param x0 线段起点横坐标。
   * @param y0 线段起点纵坐标。
   * @param x1 线段终点横坐标。
   * @param y1 线段终点纵坐标。
   * @param width 画面宽度，单位像素。
   * @param blur 笔触模糊半径。
   * @param alpha 透明度，范围为 0～1。
   * @returns 无返回值。
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

  /**
   * 叠加多层发光笔触绘制一段轨迹。
   *
   * @param x0 线段起点横坐标。
   * @param y0 线段起点纵坐标。
   * @param x1 线段终点横坐标。
   * @param y1 线段终点纵坐标。
   * @returns 无返回值。
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
    context.moveTo(x0, y0);
    context.lineTo(x1, y1);
    context.stroke();
    context.restore();

    this.hasTrailPixels = true;
    this.idleFadeTicks = 0;
  }

  /**
   * 逐步衰减轨迹画布，使已结束的轨迹自然消退。
   *
   * @returns 无返回值。
   */
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

  /**
   * 清空效果层并绘制活动触点的光晕、圆环和粒子。
   *
   * @param timestamp 轨迹采样或动画更新时间，单位毫秒。
   * @returns 无返回值。
   */
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

  /**
   * 绘制触点中心与外围光晕。
   *
   * @param context 承载当前绘制的画布上下文。
   * @param x 横坐标。
   * @param y 纵坐标。
   * @returns 无返回值。
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

  /**
   * 按触点持续时间绘制扩散圆环。
   *
   * @param context 承载当前绘制的画布上下文。
   * @param trajectory 需要绘制的活动轨迹。
   * @param timestamp 轨迹采样或动画更新时间，单位毫秒。
   * @returns 无返回值。
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
   * 按触点持续时间绘制周围粒子。
   *
   * @param context 承载当前绘制的画布上下文。
   * @param trajectory 需要绘制的活动轨迹。
   * @param timestamp 轨迹采样或动画更新时间，单位毫秒。
   * @returns 无返回值。
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
      gradient.addColorStop(0, this.glowColor(alpha));
      gradient.addColorStop(1, this.glowColor(0));

      context.fillStyle = gradient;
      context.beginPath();
      context.arc(x, y, 6, 0, Math.PI * 2);
      context.fill();
    }
  }
}
