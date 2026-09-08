import { NativeCameraFrameTiming } from 'libxmax_video.so';
import systemDateTime from '@ohos.systemDateTime';
import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import { XmaxLoggerOption } from '../../foundation/logging/XmaxLoggerOption';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';

const STATISTICS_INTERVAL_MS: number = 2000;

/** 每两秒汇总相机处理性能；CPU 统计仅覆盖 Native 采集工作线程。 */
export class CameraFrameStatistics {
  private readonly sourceWidth: number;
  private readonly sourceHeight: number;
  private configuration: string = '未配置';
  private windowStartedAtMs: number = -1;
  private outputFrameCount: number = 0;
  private droppedFrameCount: number = 0;
  private skippedFrameCount: number = 0;
  private processingTotalMs: number = 0;
  private stageFrameCount: number = 0;
  private allocationTotalMs: number = 0;
  private uvSplitTotalMs: number = 0;
  private scaleTotalMs: number = 0;
  private rotationTotalMs: number = 0;
  private uvMergeTotalMs: number = 0;
  private backend: string = '';
  private cpuStartedAtMs: number = 0;
  private cpuSampleStartedAtMs: number = 0;
  private cpuWindowValid: boolean = false;

  constructor(sourceWidth: number, sourceHeight: number) {
    this.sourceWidth = sourceWidth;
    this.sourceHeight = sourceHeight;
  }

  configure(format: RealtimeVideoFormat, captureFrameRate: number, rotation: number): void {
    this.configuration = `${this.sourceWidth}×${this.sourceHeight} @ ${captureFrameRate} fps → ` +
      `${format.width}×${format.height} @ ${format.fps} fps，旋转 ${rotation}°`;
    this.windowStartedAtMs = -1;
  }

  record(
    processingMilliseconds: number,
    droppedFrames: number,
    skippedFrames: number,
    conversionBackend: string,
    threadCpuMilliseconds?: number,
    sampleTimeMilliseconds?: number,
    timing?: NativeCameraFrameTiming
  ): void {
    if (!XmaxLogger.isEnabled(XmaxLoggerOption.PERFORMANCE)) {
      this.windowStartedAtMs = -1;
      return;
    }
    const nowMs: number = systemDateTime.getUptime(systemDateTime.TimeType.ACTIVE, false);
    if (this.windowStartedAtMs < 0) {
      // 首帧只建立基线，排除相机打开和首帧等待时间。
      this.reset(nowMs, threadCpuMilliseconds, sampleTimeMilliseconds);
      return;
    }

    this.outputFrameCount += 1;
    this.droppedFrameCount += droppedFrames;
    this.skippedFrameCount += skippedFrames;
    this.processingTotalMs += processingMilliseconds;
    this.recordStages(timing);
    this.backend = this.backend === '' ? conversionBackend :
      (this.backend === conversionBackend ? this.backend : 'mixed');
    this.cpuWindowValid = this.cpuWindowValid &&
      this.validCpuSample(threadCpuMilliseconds, sampleTimeMilliseconds);

    const elapsedMilliseconds: number = nowMs - this.windowStartedAtMs;
    if (elapsedMilliseconds < STATISTICS_INTERVAL_MS) {
      return;
    }
    const cpuPercent: string = this.cpuPercent(threadCpuMilliseconds, sampleTimeMilliseconds);
    const dropDenominator: number = this.outputFrameCount + this.droppedFrameCount;
    const dropPercent: number = this.droppedFrameCount / dropDenominator * 100;
    XmaxLogger.info(
      `相机性能（${(elapsedMilliseconds / 1000).toFixed(1)} s）\n` +
      `├─ 规格：${this.configuration}\n` +
      `├─ 转换路径：${this.backend}\n` +
      `├─ 平均帧处理：${(this.processingTotalMs / this.outputFrameCount).toFixed(2)} ms（分配+转换）\n` +
      this.stageSummary() +
      `├─ 处理线程 CPU：${cpuPercent}（单核 100%）\n` +
      `├─ Native 交付：${(this.outputFrameCount * 1000 / elapsedMilliseconds).toFixed(1)} fps，` +
      `平均间隔 ${(elapsedMilliseconds / this.outputFrameCount).toFixed(1)} ms\n` +
      `└─ 丢帧：${this.droppedFrameCount}（${dropPercent.toFixed(1)}%，不含主动跳帧），` +
      `主动采样跳帧：${this.skippedFrameCount}`,
      'CameraPerf',
      XmaxLoggerOption.PERFORMANCE
    );
    this.reset(nowMs, threadCpuMilliseconds, sampleTimeMilliseconds);
  }

  private reset(nowMs: number, cpuMs?: number, sampleMs?: number): void {
    this.windowStartedAtMs = nowMs;
    this.outputFrameCount = 0;
    this.droppedFrameCount = 0;
    this.skippedFrameCount = 0;
    this.processingTotalMs = 0;
    this.stageFrameCount = 0;
    this.allocationTotalMs = 0;
    this.uvSplitTotalMs = 0;
    this.scaleTotalMs = 0;
    this.rotationTotalMs = 0;
    this.uvMergeTotalMs = 0;
    this.backend = '';
    this.cpuStartedAtMs = cpuMs ?? 0;
    this.cpuSampleStartedAtMs = sampleMs ?? 0;
    this.cpuWindowValid = this.validCpuSample(cpuMs, sampleMs);
  }

  private validDuration(value?: number): boolean {
    return value !== undefined && Number.isFinite(value) && value >= 0;
  }

  private recordStages(timing?: NativeCameraFrameTiming): void {
    if (timing === undefined || !this.validDuration(timing.allocationMilliseconds) ||
      !this.validDuration(timing.uvSplitMilliseconds) || !this.validDuration(timing.scaleMilliseconds) ||
      !this.validDuration(timing.rotationMilliseconds) || !this.validDuration(timing.uvMergeMilliseconds)) {
      return;
    }
    this.stageFrameCount += 1;
    this.allocationTotalMs += timing.allocationMilliseconds;
    this.uvSplitTotalMs += timing.uvSplitMilliseconds ?? 0;
    this.scaleTotalMs += timing.scaleMilliseconds ?? 0;
    this.rotationTotalMs += timing.rotationMilliseconds ?? 0;
    this.uvMergeTotalMs += timing.uvMergeMilliseconds ?? 0;
  }

  private stageSummary(): string {
    // Do not average only a subset of frames and compare it to the whole-window total.
    if (this.stageFrameCount !== this.outputFrameCount) {
      return `├─ 分段平均：不可用（完整样本 ${this.stageFrameCount}/${this.outputFrameCount}）\n`;
    }
    return `├─ 输出分配/初始化：平均 ${(this.allocationTotalMs / this.stageFrameCount).toFixed(2)} ms\n` +
      `├─ UV 拆分：平均 ${(this.uvSplitTotalMs / this.stageFrameCount).toFixed(2)} ms\n` +
      `├─ 缩放：平均 ${(this.scaleTotalMs / this.stageFrameCount).toFixed(2)} ms\n` +
      `├─ 旋转：平均 ${(this.rotationTotalMs / this.stageFrameCount).toFixed(2)} ms\n` +
      `├─ UV 合并：平均 ${(this.uvMergeTotalMs / this.stageFrameCount).toFixed(2)} ms\n`;
  }

  private validCpuSample(cpuMs?: number, sampleMs?: number): boolean {
    return cpuMs !== undefined && sampleMs !== undefined &&
      Number.isFinite(cpuMs) && Number.isFinite(sampleMs) && cpuMs >= 0 && sampleMs >= 0;
  }

  private cpuPercent(cpuMs?: number, sampleMs?: number): string {
    if (!this.cpuWindowValid || cpuMs === undefined || sampleMs === undefined ||
      cpuMs < this.cpuStartedAtMs || sampleMs <= this.cpuSampleStartedAtMs) {
      return '不可用';
    }
    // 使用同一工作线程的累计 CPU 时间及其原生单调时钟，避免 ArkTS 回调排队影响 CPU 分母。
    const percent: number = (cpuMs - this.cpuStartedAtMs) /
      (sampleMs - this.cpuSampleStartedAtMs) * 100;
    return `${percent.toFixed(1)}%`;
  }
}
