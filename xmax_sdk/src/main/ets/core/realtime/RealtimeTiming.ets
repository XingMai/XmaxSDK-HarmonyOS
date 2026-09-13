import systemDateTime from '@ohos.systemDateTime';
import { XmaxError, XmaxErrorCode } from '../../foundation/errors/XmaxError';
import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import { XmaxLoggerOption } from '../../foundation/logging/XmaxLoggerOption';

type TimingClock = () => number;

/** 单次启动的计时记录；旧操作结束时不会清除新操作的记录。 */
export class RealtimeTimingRun {
  startedAt?: number;
  connectionStartedAt?: number;
  sessionStartedAt?: number;
  sessionFinishedAt?: number;
  roomJoinStartedAt?: number;
  roomJoinFinishedAt?: number;
  connectionFinishedAt?: number;
  signalStartedAt?: number;
  signalFinishedAt?: number;
  seiMatchedAt?: number;
  readyAt?: number;
  failureAt?: number;
  taskId?: string;
  finished: boolean = false;
}

/** 记录生成启动各阶段耗时，通过 PERFORMANCE 日志输出，不改变业务状态。 */
export class RealtimeTiming {
  private active: RealtimeTimingRun | null = null;
  private readonly clock: TimingClock;

  constructor(clock: TimingClock = (): number =>
    systemDateTime.getUptime(systemDateTime.TimeType.ACTIVE, true) / 1000000) {
    this.clock = clock;
  }

  begin(): RealtimeTimingRun {
    const run = new RealtimeTimingRun();
    run.startedAt = this.now();
    this.active = run;
    return run;
  }

  /** 操作体结束后停止接收阶段事件，失败摘要仍可在清理后输出。 */
  endOperation(run: RealtimeTimingRun | null): void {
    if (run !== null && this.active === run) { this.active = null; }
  }

  beginConnection(): void {
    if (this.active !== null) { this.active.connectionStartedAt = this.now(); }
  }

  beginSessionCreation(): void {
    if (this.active !== null) { this.active.sessionStartedAt = this.now(); }
  }

  finishSessionCreation(): void {
    if (this.active !== null) { this.active.sessionFinishedAt = this.now(); }
  }

  beginRoomJoin(): void {
    if (this.active !== null) { this.active.roomJoinStartedAt = this.now(); }
  }

  finishRoomJoin(): void {
    if (this.active !== null) { this.active.roomJoinFinishedAt = this.now(); }
  }

  finishConnection(): void {
    if (this.active !== null) { this.active.connectionFinishedAt = this.now(); }
  }

  beginSignal(taskId: string): void {
    const run: RealtimeTimingRun | null = this.active;
    if (run !== null) {
      run.taskId = taskId;
      run.signalStartedAt = this.now();
      run.signalFinishedAt = undefined;
      run.seiMatchedAt = undefined;
    }
  }

  finishSignal(taskId: string): void {
    if (this.active !== null && this.active.taskId === taskId) {
      this.active.signalFinishedAt = this.now();
    }
  }

  matchSEI(taskId: string): void {
    if (this.active !== null && this.active.taskId === taskId && this.active.seiMatchedAt === undefined) {
      this.active.seiMatchedAt = this.now();
    }
  }

  finish(taskId: string): void {
    const run: RealtimeTimingRun | null = this.active;
    if (run === null || run.finished || run.taskId !== taskId) { return; }
    run.readyAt = this.now();
    this.complete(run);
    if (run.startedAt !== undefined) {
      this.emit((): string => this.format(run));
    }
  }

  finishFailure(error: Object, run: RealtimeTimingRun | null): void {
    if (run === null || run.finished) { return; }
    run.failureAt = this.now();
    this.complete(run);
    const failure: XmaxError = XmaxError.from(error);
    if (failure.code !== XmaxErrorCode.CANCELLED && run.startedAt !== undefined) {
      this.emit((): string => this.formatFailure(run, failure));
    }
  }

  private complete(run: RealtimeTimingRun): void {
    run.finished = true;
    if (this.active === run) { this.active = null; }
  }

  private emit(message: () => string): void {
    try {
      XmaxLogger.info(message, 'Timing', XmaxLoggerOption.PERFORMANCE);
    } catch (_error) {
      // 日志输出失败也不能改变本次生成的结果。
    }
  }

  private now(): number | undefined {
    try {
      const value: number = this.clock();
      return Number.isFinite(value) && value >= 0 ? value : undefined;
    } catch (_error) {
      // 诊断时钟不可用不应中断生成。
      return undefined;
    }
  }

  private format(run: RealtimeTimingRun): string {
    if (run.startedAt === undefined || run.signalStartedAt === undefined ||
      run.seiMatchedAt === undefined || run.readyAt === undefined) {
      return '实时生成启动耗时不可用 (Realtime Generation Startup Timing Unavailable)';
    }
    const lines: string[] = [
      '实时生成启动耗时 (Realtime Generation Startup Timing)',
      `${XmaxLogger.localized("├─ 总耗时：", "├─ Total Duration: ")}${this.duration(run.startedAt, run.readyAt)}`
    ];
    if (run.connectionStartedAt !== undefined && run.connectionFinishedAt !== undefined) {
      lines.push(`${XmaxLogger.localized("├─ 实时连接：", "├─ Realtime Connection: ")}${this.duration(run.connectionStartedAt, run.connectionFinishedAt)}`);
    }
    lines.push(`${XmaxLogger.localized("├─ 等待生成结果流确认：", "├─ Waiting for Result Stream Confirmation: ")}${this.duration(run.signalStartedAt, run.seiMatchedAt)}`);
    lines.push(`${XmaxLogger.localized("└─ 结果流确认到首帧就绪：", "└─ Result Stream Confirmation to First Frame Ready: ")}${this.duration(run.seiMatchedAt, run.readyAt)}`);
    return lines.join('\n');
  }

  private formatFailure(run: RealtimeTimingRun, error: XmaxError): string {
    const lines: string[] = [
      '实时生成启动未完成耗时 (Incomplete Realtime Generation Startup Timing)',
      `${XmaxLogger.localized("├─ 已耗时：", "├─ Elapsed Time: ")}${this.duration(run.startedAt, run.failureAt)}`,
      `${XmaxLogger.localized("├─ 停留阶段：", "├─ Current Stage: ")}${this.pendingStage(run)}`
    ];
    this.appendDetail(lines, XmaxLogger.localized("服务端会话创建", "Server Session Creation"), run.sessionStartedAt, run.sessionFinishedAt ?? run.failureAt);
    this.appendDetail(lines, XmaxLogger.localized("RTC 房间连接", "RTC Room Connection"), run.roomJoinStartedAt, run.roomJoinFinishedAt ?? run.failureAt);
    this.appendDetail(lines, XmaxLogger.localized("实时连接", "Realtime Connection"), run.connectionStartedAt, run.connectionFinishedAt ?? run.failureAt);
    this.appendDetail(lines, XmaxLogger.localized("等待生成结果流确认", "Waiting for Result Stream Confirmation"), run.signalStartedAt, run.seiMatchedAt ?? run.failureAt);
    this.appendDetail(lines, XmaxLogger.localized("结果流确认后等待首帧", "Waiting for First Frame after Stream Confirmation"), run.seiMatchedAt, run.failureAt);
    lines.push(`${XmaxLogger.localized("└─ 失败原因：", "└─ Failure Reason: ")}${error.message}`);
    return lines.join('\n');
  }

  private pendingStage(run: RealtimeTimingRun): string {
    if (run.seiMatchedAt !== undefined) { return XmaxLogger.localized("结果流已确认，正在等待首帧", "Result stream confirmed, waiting for the first frame"); }
    if (run.signalStartedAt !== undefined) { return XmaxLogger.localized("正在等待生成结果流确认", "Waiting for result stream confirmation"); }
    if (run.connectionFinishedAt !== undefined) { return XmaxLogger.localized("连接完成后准备生成", "Preparing generation after connection"); }
    if (run.roomJoinStartedAt !== undefined && run.roomJoinFinishedAt === undefined) {
      return XmaxLogger.localized("正在连接 RTC 房间", "Joining the RTC room");
    }
    if (run.sessionFinishedAt !== undefined) { return XmaxLogger.localized("RTC 连接准备", "Preparing the RTC connection"); }
    if (run.sessionStartedAt !== undefined) { return XmaxLogger.localized("服务端会话创建", "Server Session Creation"); }
    return XmaxLogger.localized("调用与本地准备", "Call and local preparation");
  }

  private appendDetail(lines: string[], title: string, start?: number, end?: number): void {
    const value: number | undefined = this.milliseconds(start, end);
    if (value !== undefined && value >= 1) { lines.push(`├─ ${title}${XmaxLogger.localized('：', ': ')}${value.toFixed(1)} ms`); }
  }

  private milliseconds(start?: number, end?: number): number | undefined {
    return start !== undefined && end !== undefined && end >= start ? end - start : undefined;
  }

  private duration(start?: number, end?: number): string {
    return `${(this.milliseconds(start, end) ?? 0).toFixed(1)} ms`;
  }
}
