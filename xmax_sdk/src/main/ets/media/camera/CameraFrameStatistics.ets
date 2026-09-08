import { XmaxLogger } from '../../foundation/logging/XmaxLogger';

const STATISTICS_INTERVAL_MS: number = 2000;

/** 统计相机视频帧处理性能。 */
export class CameraFrameStatistics {
  // 统计窗口
  private windowStartedAtMs: number = Date.now();
  private outputFrameCount: number = 0;
  private droppedFrameCount: number = 0;
  private skippedFrameCount: number = 0;
  private processingTimes: Array<number> = [];
  private deliveryIntervals: Array<number> = [];

  // 帧时间
  private lastOutputAtMs: number = 0;

  record(
    processingMilliseconds: number,
    droppedFrames: number,
    skippedFrames: number
  ): void {
    const nowMs: number = Date.now();
    if (this.lastOutputAtMs > 0) {
      this.deliveryIntervals.push(nowMs - this.lastOutputAtMs);
    }
    this.lastOutputAtMs = nowMs;

    this.outputFrameCount += 1;
    this.droppedFrameCount += droppedFrames;
    this.skippedFrameCount += skippedFrames;
    this.processingTimes.push(processingMilliseconds);

    const elapsedMilliseconds: number = nowMs - this.windowStartedAtMs;
    if (elapsedMilliseconds < STATISTICS_INTERVAL_MS) {
      return;
    }

    this.log(elapsedMilliseconds);
    this.reset(nowMs);
  }

  private log(elapsedMilliseconds: number): void {
    const elapsedSeconds: number = elapsedMilliseconds / 1000;
    const inputFrameCount: number = this.outputFrameCount +
      this.droppedFrameCount + this.skippedFrameCount;
    const inputFrameRate: number = inputFrameCount / elapsedSeconds;
    const outputFrameRate: number = this.outputFrameCount / elapsedSeconds;

    XmaxLogger.debug(
      `Native 帧处理\n` +
      `├─ 输入：${inputFrameRate.toFixed(1)} fps\n` +
      `├─ 输出：${outputFrameRate.toFixed(1)} fps，` +
      `取样跳过 ${this.skippedFrameCount}，丢帧 ${this.droppedFrameCount}\n` +
      `├─ 转换：平均 ${this.average(this.processingTimes).toFixed(1)} ms，` +
      `P95 ${this.percentile95(this.processingTimes).toFixed(1)} ms，` +
      `最大 ${this.maximum(this.processingTimes).toFixed(1)} ms\n` +
      `└─ 帧间隔：平均 ${this.average(this.deliveryIntervals).toFixed(1)} ms，` +
      `P95 ${this.percentile95(this.deliveryIntervals).toFixed(1)} ms`,
      'Camera'
    );
  }

  private reset(nowMs: number): void {
    this.windowStartedAtMs = nowMs;
    this.outputFrameCount = 0;
    this.droppedFrameCount = 0;
    this.skippedFrameCount = 0;
    this.processingTimes = [];
    this.deliveryIntervals = [];
  }

  private average(values: Array<number>): number {
    if (values.length === 0) {
      return 0;
    }

    let total: number = 0;
    values.forEach((value: number): void => {
      total += value;
    });
    return total / values.length;
  }

  private percentile95(values: Array<number>): number {
    if (values.length === 0) {
      return 0;
    }

    const sortedValues: Array<number> = values.slice();
    sortedValues.sort((left: number, right: number): number => left - right);
    const index: number = Math.min(
      sortedValues.length - 1,
      Math.ceil(sortedValues.length * 0.95) - 1
    );
    return sortedValues[index];
  }

  private maximum(values: Array<number>): number {
    let maximum: number = 0;
    values.forEach((value: number): void => {
      maximum = Math.max(maximum, value);
    });
    return maximum;
  }
}
