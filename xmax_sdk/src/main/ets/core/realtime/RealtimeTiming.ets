//
//  RealtimeTiming.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import systemDateTime from '@ohos.systemDateTime';
import { XmaxError, XmaxErrorCode } from '../../foundation/errors/XmaxError';
import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import { XmaxLoggerOption } from '../../foundation/logging/XmaxLoggerOption';

/**
 * Supplies monotonic time for generation startup measurements, in milliseconds.
 *
 * @returns The monotonic time, in milliseconds.
 */
type TimingClock = () => number;

/** A startup timing record whose completion cannot clear a newer operation's record. */
export class RealtimeTimingRun {

  // Overall startup timing

  /** The startup origin on the monotonic clock, in milliseconds. */
  startedAt?: number;

  // Connection and service session timing

  /** The monotonic connection start time, in milliseconds. */
  connectionStartedAt?: number;

  /** The monotonic session creation start time, in milliseconds. */
  sessionStartedAt?: number;

  /** The monotonic session creation completion time, in milliseconds. */
  sessionFinishedAt?: number;

  /** The monotonic room join start time, in milliseconds. */
  roomJoinStartedAt?: number;

  /** The monotonic room join completion time, in milliseconds. */
  roomJoinFinishedAt?: number;

  /** The monotonic connection completion time, in milliseconds. */
  connectionFinishedAt?: number;

  // Generation signaling and result readiness timing

  /** The monotonic generation signal start time, in milliseconds. */
  signalStartedAt?: number;

  /** The monotonic generation signal submission time, in milliseconds. */
  signalFinishedAt?: number;

  /** The monotonic task confirmation time, in milliseconds. */
  seiMatchedAt?: number;

  /** The monotonic result readiness time, in milliseconds. */
  readyAt?: number;

  /** The monotonic failure time, in milliseconds. */
  failureAt?: number;

  // Task identity and timing completion

  /** The generation task identifier. */
  taskId?: string;

  /** Whether this timing record has completed. */
  finished: boolean = false;
}

/** Records generation startup phases for PERFORMANCE logs without changing lifecycle state. */
export class RealtimeTiming {

  // Current timing record

  /** The timing record currently receiving startup phase events. */
  private active: RealtimeTimingRun | null = null;

  // Monotonic clock dependency

  /** The monotonic clock used for elapsed-time measurements. */
  private readonly clock: TimingClock;

  /** Creates a generation startup timer. */
  constructor(
    clock: TimingClock = (): number =>
      systemDateTime.getUptime(
        systemDateTime.TimeType.ACTIVE,
        true
      ) / 1000000
  ) {
    this.clock = clock;
  }

  /**
   * Begins a startup measurement and replaces the record receiving phase events.
   *
   * @returns The startup timing record.
   */
  begin(): RealtimeTimingRun {
    const run = new RealtimeTimingRun();
    run.startedAt = this.now();
    this.active = run;
    return run;
  }

  /**
   * Stops phase events after the operation body ends, retaining failure timing for cleanup
   * completion.
   *
   * @param run The current startup timing record.
   */
  endOperation(
    run: RealtimeTimingRun | null
  ): void {
    if (run !== null && this.active === run) { this.active = null; }
  }

  /** Records the start of realtime connection. */
  beginConnection(): void {
    if (this.active !== null) { this.active.connectionStartedAt = this.now(); }
  }

  /** Records the start of server session creation. */
  beginSessionCreation(): void {
    if (this.active !== null) { this.active.sessionStartedAt = this.now(); }
  }

  /** Records server session creation completion. */
  finishSessionCreation(): void {
    if (this.active !== null) { this.active.sessionFinishedAt = this.now(); }
  }

  /** Records the start of RTC room joining. */
  beginRoomJoin(): void {
    if (this.active !== null) { this.active.roomJoinStartedAt = this.now(); }
  }

  /** Records RTC room join completion. */
  finishRoomJoin(): void {
    if (this.active !== null) { this.active.roomJoinFinishedAt = this.now(); }
  }

  /** Records realtime connection completion. */
  finishConnection(): void {
    if (this.active !== null) { this.active.connectionFinishedAt = this.now(); }
  }

  /**
   * Associates a generation task and starts result confirmation timing.
   *
   * @param taskId The current generation task identifier.
   */
  beginSignal(
    taskId: string
  ): void {
    const run: RealtimeTimingRun | null = this.active;
    if (run !== null) {
      run.taskId = taskId;
      run.signalStartedAt = this.now();
      run.signalFinishedAt = undefined;
      run.seiMatchedAt = undefined;
    }
  }

  /**
   * Records completion of the current task's start signal submission.
   *
   * @param taskId The current generation task identifier.
   */
  finishSignal(
    taskId: string
  ): void {
    if (this.active !== null && this.active.taskId === taskId) {
      this.active.signalFinishedAt = this.now();
    }
  }

  /**
   * Records the first matching SEI or static-task start confirmation.
   *
   * @param taskId The current generation task identifier.
   */
  matchSEI(
    taskId: string
  ): void {
    if (this.active !== null && this.active.taskId === taskId && this.active.seiMatchedAt === undefined) {
      this.active.seiMatchedAt = this.now();
    }
  }

  /**
   * Completes successful startup timing and logs phase durations.
   *
   * @param taskId The current generation task identifier.
   * @param confirmationOnly Whether task confirmation completes startup for a static task awaiting
   * interaction.
   */
  finish(
    taskId: string,
    confirmationOnly: boolean = false
  ): void {
    const run: RealtimeTimingRun | null = this.active;
    if (run === null || run.finished || run.taskId !== taskId) { return; }

    run.readyAt = this.now();
    this.complete(run);

    if (run.startedAt !== undefined) {
      this.emit((): string => this.format(
        run,
        confirmationOnly
      ));
    }
  }

  /**
   * Completes a startup record and logs failure timing for non-cancellation errors.
   *
   * @param error The startup failure whose elapsed time and stage are recorded.
   * @param run The current startup timing record.
   */
  finishFailure(
    error: Object,
    run: RealtimeTimingRun | null
  ): void {
    if (run === null || run.finished) { return; }

    run.failureAt = this.now();
    this.complete(run);

    const failure: XmaxError = XmaxError.from(error);
    if (failure.code !== XmaxErrorCode.CANCELLED && run.startedAt !== undefined) {
      this.emit((): string => this.formatFailure(
        run,
        failure
      ));
    }
  }

  /**
   * Marks a startup record complete and stops accepting its phase events.
   *
   * @param run The current startup timing record.
   */
  private complete(
    run: RealtimeTimingRun
  ): void {
    run.finished = true;
    if (this.active === run) { this.active = null; }
  }

  /**
   * Lazily formats enabled performance logs without allowing logging failure to affect generation.
   *
   * @param message The lazy performance log message.
   */
  private emit(
    message: () => string
  ): void {
    try {
      XmaxLogger.info(
        message,
        'Timing',
        XmaxLoggerOption.PERFORMANCE
      );
    } catch (_error) {
      // Logging failure must not change the generation result.
    }
  }

  /**
   * Reads monotonic time, omitting the timing point if the clock fails.
   *
   * @returns The monotonic time in milliseconds, or undefined if unavailable.
   */
  private now(): number | undefined {
    try {
      const value: number = this.clock();
      return Number.isFinite(value) && value >= 0 ? value : undefined;
    } catch (_error) {
      // An unavailable diagnostic clock must not interrupt generation.
      return undefined;
    }
  }

  /**
   * Formats startup phase durations from a completed record.
   *
   * @param run The current startup timing record.
   * @param confirmationOnly Whether to report task confirmation timing only.
   *
   * @returns The startup timing summary for performance logs.
   */
  private format(
    run: RealtimeTimingRun,
    confirmationOnly: boolean
  ): string {
    if (run.startedAt === undefined || run.signalStartedAt === undefined ||
      run.seiMatchedAt === undefined || run.readyAt === undefined) {
      return '实时生成启动耗时不可用 (Realtime Generation Startup Timing Unavailable)';
    }

    const lines: string[] = [
      confirmationOnly ? '静态生成任务确认耗时 (Static Generation Confirmation Timing)' :
        '实时生成启动耗时 (Realtime Generation Startup Timing)',
      `${XmaxLogger.localized("├─ 总耗时：", "├─ Total Duration: ")}${this.duration(run.startedAt, run.readyAt)}`
    ];
    if (run.connectionStartedAt !== undefined && run.connectionFinishedAt !== undefined) {
      lines.push(`${XmaxLogger.localized("├─ 实时连接：", "├─ Realtime Connection: ")}${this.duration(run.connectionStartedAt, run.connectionFinishedAt)}`);
    }
    lines.push(`${XmaxLogger.localized("├─ 等待生成结果流确认：", "├─ Waiting for Result Stream Confirmation: ")}${this.duration(run.signalStartedAt, run.seiMatchedAt)}`);
    if (!confirmationOnly) {
      lines.push(`${XmaxLogger.localized("└─ 结果流确认到首帧就绪：", "└─ Result Stream Confirmation to First Frame Ready: ")}${this.duration(run.seiMatchedAt, run.readyAt)}`);
    }

    return lines.join('\n');
  }

  /**
   * Formats failure stage, elapsed duration, and reason.
   *
   * @param run The current startup timing record.
   * @param error The startup failure to include in the timing record.
   *
   * @returns The failure timing summary for logging.
   */
  private formatFailure(
    run: RealtimeTimingRun,
    error: XmaxError
  ): string {
    const lines: string[] = [
      '实时生成启动未完成耗时 (Incomplete Realtime Generation Startup Timing)',
      `${XmaxLogger.localized("├─ 已耗时：", "├─ Elapsed Time: ")}${this.duration(run.startedAt, run.failureAt)}`,
      `${XmaxLogger.localized("├─ 停留阶段：", "├─ Current Stage: ")}${this.pendingStage(run)}`
    ];

    this.appendDetail(
      lines,
      XmaxLogger.localized(
        "服务端会话创建",
        "Server Session Creation"
      ),
      run.sessionStartedAt,
      run.sessionFinishedAt ?? run.failureAt
    );
    this.appendDetail(
      lines,
      XmaxLogger.localized(
        "RTC 房间连接",
        "RTC Room Connection"
      ),
      run.roomJoinStartedAt,
      run.roomJoinFinishedAt ?? run.failureAt
    );
    this.appendDetail(
      lines,
      XmaxLogger.localized(
        "实时连接",
        "Realtime Connection"
      ),
      run.connectionStartedAt,
      run.connectionFinishedAt ?? run.failureAt
    );
    this.appendDetail(
      lines,
      XmaxLogger.localized(
        "等待生成结果流确认",
        "Waiting for Result Stream Confirmation"
      ),
      run.signalStartedAt,
      run.seiMatchedAt ?? run.failureAt
    );
    this.appendDetail(
      lines,
      XmaxLogger.localized(
        "结果流确认后等待首帧",
        "Waiting for First Frame after Stream Confirmation"
      ),
      run.seiMatchedAt,
      run.failureAt
    );

    lines.push(`${XmaxLogger.localized("└─ 失败原因：", "└─ Failure Reason: ")}${error.message}`);

    return lines.join('\n');
  }

  /**
   * Resolves the unfinished startup stage from timing points.
   *
   * @param run The current startup timing record.
   *
   * @returns The readable incomplete stage name.
   */
  private pendingStage(
    run: RealtimeTimingRun
  ): string {
    if (run.seiMatchedAt !== undefined) {
      return XmaxLogger.localized(
        "结果流已确认，正在等待首帧",
        "Result stream confirmed, waiting for the first frame"
      );
    }
    if (run.signalStartedAt !== undefined) {
      return XmaxLogger.localized(
        "正在等待生成结果流确认",
        "Waiting for result stream confirmation"
      );
    }
    if (run.connectionFinishedAt !== undefined) {
      return XmaxLogger.localized(
        "连接完成后准备生成",
        "Preparing generation after connection"
      );
    }
    if (run.roomJoinStartedAt !== undefined && run.roomJoinFinishedAt === undefined) {
      return XmaxLogger.localized(
        "正在连接 RTC 房间",
        "Joining the RTC room"
      );
    }
    if (run.sessionFinishedAt !== undefined) {
      return XmaxLogger.localized(
        "RTC 连接准备",
        "Preparing the RTC connection"
      );
    }
    if (run.sessionStartedAt !== undefined) {
      return XmaxLogger.localized(
        "服务端会话创建",
        "Server Session Creation"
      );
    }
    return XmaxLogger.localized(
      "调用与本地准备",
      "Call and local preparation"
    );
  }

  /**
   * Appends a valid phase duration of at least one millisecond.
   *
   * @param lines The log lines receiving formatted content.
   * @param title The phase or operation name.
   * @param start The phase start, using the same clock as its end.
   * @param end The phase end, using the same clock as its start.
   */
  private appendDetail(
    lines: string[],
    title: string,
    start?: number,
    end?: number
  ): void {
    const value: number | undefined = this.milliseconds(
      start,
      end
    );
    if (value !== undefined && value >= 1) { lines.push(`├─ ${title}${XmaxLogger.localized('：', ': ')}${value.toFixed(1)} ms`); }
  }

  /**
   * Returns the millisecond interval between valid timing points.
   *
   * @param start The phase start, using the same clock as its end.
   * @param end The phase end, using the same clock as its start.
   *
   * @returns The nonnegative duration, or undefined for missing or unordered points.
   */
  private milliseconds(
    start?: number,
    end?: number
  ): number | undefined {
    return start !== undefined && end !== undefined && end >= start ? end - start : undefined;
  }

  /**
   * Formats a timing interval in milliseconds.
   *
   * @param start The phase start, using the same clock as its end.
   * @param end The phase end, using the same clock as its start.
   *
   * @returns The millisecond text with one decimal place, using zero for invalid points.
   */
  private duration(
    start?: number,
    end?: number
  ): string {
    return `${(this.milliseconds(start, end) ?? 0).toFixed(1)} ms`;
  }
}
