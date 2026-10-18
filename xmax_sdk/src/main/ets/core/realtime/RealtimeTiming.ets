//
//  RealtimeTiming.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import systemDateTime from '@ohos.systemDateTime';
import { XmaxError, XmaxErrorCode } from '../../foundation/errors/XmaxError';
import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import { XmaxLoggerOption } from '../../foundation/logging/XmaxLoggerOption';

/**
 * 提供生成启动计时所需的单调时间，单位毫秒。
 *
 * @returns 以毫秒为单位的单调时间。
 */
type TimingClock = () => number;

/** 单次启动的计时记录；旧操作结束时不会清除新操作的记录。 */
export class RealtimeTimingRun {

  /** 整体启动计时 */
  startedAt?: number;

  /** 连接与服务会话计时 */
  connectionStartedAt?: number;
  sessionStartedAt?: number;
  sessionFinishedAt?: number;
  roomJoinStartedAt?: number;
  roomJoinFinishedAt?: number;
  connectionFinishedAt?: number;

  /** 生成信令与结果就绪计时 */
  signalStartedAt?: number;
  signalFinishedAt?: number;
  seiMatchedAt?: number;
  readyAt?: number;
  failureAt?: number;

  /** 任务身份与计时完成状态 */
  taskId?: string;
  finished: boolean = false;
}

/** 记录生成启动各阶段耗时，通过 PERFORMANCE 日志输出，不改变业务状态。 */
export class RealtimeTiming {

  /** 当前计时记录 */
  private active: RealtimeTimingRun | null = null;

  /** 单调计时依赖 */
  private readonly clock: TimingClock;

  /**
   * 创建生成启动计时器。
   *
   * @param clock 提供单调时间的计时函数，单位毫秒。
   * @returns 新建的 RealtimeTiming 实例。
   */
  constructor(clock: TimingClock = (): number =>
    systemDateTime.getUptime(systemDateTime.TimeType.ACTIVE, true) / 1000000) {
    this.clock = clock;
  }

  /**
   * 开始一次生成启动计时，替换正在接收阶段事件的记录。
   *
   * @returns 本次启动的计时记录。
   */
  begin(): RealtimeTimingRun {
    const run = new RealtimeTimingRun();
    run.startedAt = this.now();
    this.active = run;
    return run;
  }

  /**
   * 操作体结束后停止接收阶段事件，失败摘要仍可在清理后输出。
   *
   * @param run 当前生成启动的计时记录。
   * @returns 无返回值。
   */
  endOperation(run: RealtimeTimingRun | null): void {
    if (run !== null && this.active === run) { this.active = null; }
  }

  /**
   * 记录实时连接开始的时间。
   *
   * @returns 无返回值。
   */
  beginConnection(): void {
    if (this.active !== null) { this.active.connectionStartedAt = this.now(); }
  }

  /**
   * 记录服务端会话创建开始的时间。
   *
   * @returns 无返回值。
   */
  beginSessionCreation(): void {
    if (this.active !== null) { this.active.sessionStartedAt = this.now(); }
  }

  /**
   * 记录服务端会话创建完成的时间。
   *
   * @returns 无返回值。
   */
  finishSessionCreation(): void {
    if (this.active !== null) { this.active.sessionFinishedAt = this.now(); }
  }

  /**
   * 记录加入 RTC 房间开始的时间。
   *
   * @returns 无返回值。
   */
  beginRoomJoin(): void {
    if (this.active !== null) { this.active.roomJoinStartedAt = this.now(); }
  }

  /**
   * 记录加入 RTC 房间完成的时间。
   *
   * @returns 无返回值。
   */
  finishRoomJoin(): void {
    if (this.active !== null) { this.active.roomJoinFinishedAt = this.now(); }
  }

  /**
   * 记录实时连接完成的时间。
   *
   * @returns 无返回值。
   */
  finishConnection(): void {
    if (this.active !== null) { this.active.connectionFinishedAt = this.now(); }
  }

  /**
   * 关联生成任务并开始记录结果流确认耗时。
   *
   * @param taskId 当前生成任务标识。
   * @returns 无返回值。
   */
  beginSignal(taskId: string): void {
    const run: RealtimeTimingRun | null = this.active;
    if (run !== null) {
      run.taskId = taskId;
      run.signalStartedAt = this.now();
      run.signalFinishedAt = undefined;
      run.seiMatchedAt = undefined;
    }
  }

  /**
   * 记录当前任务启动信令发送完成的时间。
   *
   * @param taskId 当前生成任务标识。
   * @returns 无返回值。
   */
  finishSignal(taskId: string): void {
    if (this.active !== null && this.active.taskId === taskId) {
      this.active.signalFinishedAt = this.now();
    }
  }

  /**
   * 首次匹配当前生成任务的 SEI 时记录结果流确认时间。
   *
   * @param taskId 当前生成任务标识。
   * @returns 无返回值。
   */
  matchSEI(taskId: string): void {
    if (this.active !== null && this.active.taskId === taskId && this.active.seiMatchedAt === undefined) {
      this.active.seiMatchedAt = this.now();
    }
  }

  /**
   * 结束当前任务的启动计时，并输出成功启动的各阶段耗时。
   *
   * @param taskId 当前生成任务标识。
   * @returns 无返回值。
   */
  finish(taskId: string): void {
    const run: RealtimeTimingRun | null = this.active;
    if (run === null || run.finished || run.taskId !== taskId) { return; }
    run.readyAt = this.now();
    this.complete(run);
    if (run.startedAt !== undefined) {
      this.emit((): string => this.format(run));
    }
  }

  /**
   * 结束指定启动记录，并在非取消错误时输出失败阶段耗时。
   *
   * @param error 当前操作失败或终止的原因。
   * @param run 当前生成启动的计时记录。
   * @returns 无返回值。
   */
  finishFailure(error: Object, run: RealtimeTimingRun | null): void {
    if (run === null || run.finished) { return; }
    run.failureAt = this.now();
    this.complete(run);
    const failure: XmaxError = XmaxError.from(error);
    if (failure.code !== XmaxErrorCode.CANCELLED && run.startedAt !== undefined) {
      this.emit((): string => this.formatFailure(run, failure));
    }
  }

  /**
   * 标记启动记录结束，并停止接收该记录的阶段事件。
   *
   * @param run 当前生成启动的计时记录。
   * @returns 无返回值。
   */
  private complete(run: RealtimeTimingRun): void {
    run.finished = true;
    if (this.active === run) { this.active = null; }
  }

  /**
   * 按性能日志配置延迟生成计时文本，日志失败不影响业务结果。
   *
   * @param message 日志内容、错误说明或收到的信令文本。
   * @returns 无返回值。
   */
  private emit(message: () => string): void {
    try {
      XmaxLogger.info(message, 'Timing', XmaxLoggerOption.PERFORMANCE);
    } catch (_error) {
      // 日志输出失败也不能改变本次生成的结果。
    }
  }

  /**
   * 读取有效的单调计时时间，时钟失败时跳过该计时节点。
   *
   * @returns 当前单调时间，单位毫秒；不可用时返回 undefined。
   */
  private now(): number | undefined {
    try {
      const value: number = this.clock();
      return Number.isFinite(value) && value >= 0 ? value : undefined;
    } catch (_error) {
      // 诊断时钟不可用不应中断生成。
      return undefined;
    }
  }

  /**
   * 将完整启动记录转换为各阶段耗时摘要。
   *
   * @param run 当前生成启动的计时记录。
   * @returns 可供性能日志输出的启动耗时文本。
   */
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

  /**
   * 生成包含失败阶段、已耗时和错误原因的计时摘要。
   *
   * @param run 当前生成启动的计时记录。
   * @param error 当前操作失败或终止的原因。
   * @returns 可供日志输出的失败耗时说明。
   */
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

  /**
   * 根据计时节点判断生成启动停留的阶段。
   *
   * @param run 当前生成启动的计时记录。
   * @returns 当前未完成阶段的可读名称。
   */
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

  /**
   * 将有效且至少一毫秒的阶段耗时追加到日志行。
   *
   * @param lines 需要追加内容的日志行数组。
   * @param title 日志所描述的阶段或操作名称。
   * @param start 阶段开始时间，与结束时间使用相同计时基准。
   * @param end 阶段结束时间，与开始时间使用相同计时基准。
   * @returns 无返回值。
   */
  private appendDetail(lines: string[], title: string, start?: number, end?: number): void {
    const value: number | undefined = this.milliseconds(start, end);
    if (value !== undefined && value >= 1) { lines.push(`├─ ${title}${XmaxLogger.localized('：', ': ')}${value.toFixed(1)} ms`); }
  }

  /**
   * 计算两个有效计时节点之间的毫秒差。
   *
   * @param start 阶段开始时间，与结束时间使用相同计时基准。
   * @param end 阶段结束时间，与开始时间使用相同计时基准。
   * @returns 非负耗时；节点缺失或顺序无效时返回 undefined。
   */
  private milliseconds(start?: number, end?: number): number | undefined {
    return start !== undefined && end !== undefined && end >= start ? end - start : undefined;
  }

  /**
   * 将计时节点间隔格式化为带单位的毫秒文本。
   *
   * @param start 阶段开始时间，与结束时间使用相同计时基准。
   * @param end 阶段结束时间，与开始时间使用相同计时基准。
   * @returns 保留一位小数的毫秒文本；节点无效时使用 0。
   */
  private duration(start?: number, end?: number): string {
    return `${(this.milliseconds(start, end) ?? 0).toFixed(1)} ms`;
  }
}
