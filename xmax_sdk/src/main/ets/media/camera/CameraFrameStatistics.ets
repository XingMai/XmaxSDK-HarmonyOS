import systemDateTime from '@ohos.systemDateTime';
import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import { XmaxLoggerOption } from '../../foundation/logging/XmaxLoggerOption';

const STATISTICS_INTERVAL_MS: number = 2000;

/** 每两秒汇总相机处理性能；CPU 统计仅覆盖 Native 采集工作线程。 */
export class CameraFrameStatistics {
  private windowStartedAtMs: number = -1;
  private outputFrameCount: number = 0;
  private processingTotalMs: number = 0;
  private cpuStartedAtMs: number = 0;
  private cpuSampleStartedAtMs: number = 0;
  private cpuWindowValid: boolean = false;

  restart(): void {
    this.windowStartedAtMs = -1;
  }

  record(
    processingMilliseconds: number,
    threadCpuMilliseconds?: number,
    sampleTimeMilliseconds?: number
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
    this.processingTotalMs += processingMilliseconds;
    this.cpuWindowValid = this.cpuWindowValid &&
      this.validCpuSample(threadCpuMilliseconds, sampleTimeMilliseconds);

    const elapsedMilliseconds: number = nowMs - this.windowStartedAtMs;
    if (elapsedMilliseconds < STATISTICS_INTERVAL_MS) {
      return;
    }
    const cpuPercent: string = this.cpuPercent(threadCpuMilliseconds, sampleTimeMilliseconds);
    XmaxLogger.info(
      '相机性能 (Camera Performance)\n' +
      `├─ 平均帧处理：${(this.processingTotalMs / this.outputFrameCount).toFixed(2)} ms\n` +
      `├─ 处理线程 CPU：${cpuPercent}\n` +
      `└─ Native 交付：${(this.outputFrameCount * 1000 / elapsedMilliseconds).toFixed(1)} fps，` +
      `平均间隔 ${(elapsedMilliseconds / this.outputFrameCount).toFixed(1)} ms`,
      'Camera',
      XmaxLoggerOption.PERFORMANCE
    );
    this.reset(nowMs, threadCpuMilliseconds, sampleTimeMilliseconds);
  }

  private reset(nowMs: number, cpuMs?: number, sampleMs?: number): void {
    this.windowStartedAtMs = nowMs;
    this.outputFrameCount = 0;
    this.processingTotalMs = 0;
    this.cpuStartedAtMs = cpuMs ?? 0;
    this.cpuSampleStartedAtMs = sampleMs ?? 0;
    this.cpuWindowValid = this.validCpuSample(cpuMs, sampleMs);
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
