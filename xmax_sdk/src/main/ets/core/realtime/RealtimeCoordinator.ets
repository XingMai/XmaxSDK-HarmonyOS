//
//  RealtimeCoordinator.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { XmaxError, XmaxErrorCode } from '../../foundation/errors/XmaxError';
import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import { RealtimeConnectionState, RealtimeReason, RealtimeState, RealtimeStateListener } from '../../service/realtime/RealtimeState';
import { XmaxRealtimeErrorManager } from './XmaxRealtimeErrorManager';

/** 实时操作分类，用于限制互斥操作并确定取消范围。 */
export enum RealtimeOperationKind {
  MEDIA,
  PLAYBACK,
  CONNECTION,
  GENERATION,
  CAMERA_SWITCH,
  CONFIGURATION
}

/** 清理范围由小到大，较大的范围包含较小的范围。 */
export enum RealtimeTerminationScope {
  CONNECTION,
  ALL
}

/**
 * 操作取消时接收终止错误的回调。
 *
 * @param error 当前操作失败或终止的原因。
 * @returns 无返回值。
 */
type CancellationListener = (error: XmaxError) => void;

/**
 * 按指定范围清理实时资源，并返回已关闭的会话标识。
 *
 * @param scope 需要释放资源的清理范围。
 * @param taskId 当前生成任务标识。
 * @returns 资源清理完成的 Promise，携带已关闭会话标识；无会话时为 undefined。
 */
type CleanupHandler = (scope: RealtimeTerminationScope, taskId: string) => Promise<string | undefined>;

/** 跨异步边界验证操作所有权，并取消不再需要的结果等待。 */
export class RealtimeOperationToken {

  /** 操作有效性与取消通知 */
  private valid: boolean = true;
  private failure: XmaxError | null = null;
  private readonly cancellationListeners: Set<CancellationListener> = new Set();

  /** 失败资源清理范围 */
  private storedFailureScope: RealtimeTerminationScope | null;

  /**
   * 创建实时操作令牌。
   *
   * @param failureScope 操作失败时的资源清理范围；null 表示由调用处自行回滚。
   * @returns 新建的 RealtimeOperationToken 实例。
   */
  constructor(failureScope: RealtimeTerminationScope | null) {
    this.storedFailureScope = failureScope;
  }

  /**
   * 判断当前操作是否仍持有有效的执行权限。
   *
   * @returns 操作有效时返回 true，已取消或结束时返回 false。
   */
  get isCurrent(): boolean {
    return this.valid;
  }

  /**
   * 读取操作失败后应清理的资源范围。
   *
   * @returns 清理范围；null 表示由调用处自行回滚。
   */
  get failureScope(): RealtimeTerminationScope | null {
    return this.storedFailureScope;
  }

  /**
   * 读取导致操作终止的错误。
   *
   * @returns 终止错误；没有错误原因时返回 null。
   */
  get terminalError(): XmaxError | null {
    return this.failure;
  }

  /**
   * 登记当前操作失败后需要释放的资源范围。
   *
   * @param scope 需要释放资源的清理范围。
   * @returns 无返回值。
   */
  setFailureScope(scope: RealtimeTerminationScope | null): void {
    this.storedFailureScope = scope;
  }

  /**
   * 验证操作有效性；已失效时抛出终止错误或取消错误。
   *
   * @returns 无返回值。
   */
  ensureCurrent(): void {
    if (!this.valid) {
      throw this.failure ?? RealtimeOperationToken.cancelledError();
    }
  }

  /**
   * 使操作失效，并通知所有正在等待取消的调用。
   *
   * @param error 当前操作失败或终止的原因。
   * @returns 无返回值。
   */
  invalidate(error?: XmaxError): void {
    if (error !== undefined && this.failure === null) {
      this.failure = error;
    }
    this.valid = false;
    const reason: XmaxError = this.failure ?? RealtimeOperationToken.cancelledError();
    this.cancellationListeners.forEach((listener: CancellationListener): void => listener(reason));
    this.cancellationListeners.clear();
  }

  /**
   * 等待结果并响应当前操作取消；仅适用于确认或首帧等待，资源变更仍需等待实际完成后清理。
   *
   * @param promise 需要等待且可被当前操作取消的结果 Promise。
   * @returns 原始等待结果；当前操作取消时拒绝的 Promise。
   */
  wait<T>(promise: Promise<T>): Promise<T> {
    return new Promise<T>((resolve: (value: T) => void, reject: (error: XmaxError) => void): void => {
      const cancel: CancellationListener = (error: XmaxError): void => reject(error);
      if (this.valid) {
        this.cancellationListeners.add(cancel);
      } else {
        reject(this.failure ?? RealtimeOperationToken.cancelledError());
      }
      // 即使已经取消也观察原 Promise，消费它可能晚到的拒绝。
      promise.then((value: T): void => {
        this.cancellationListeners.delete(cancel);
        try {
          this.ensureCurrent();
          resolve(value);
        } catch (error) {
          reject(XmaxError.from(error));
        }
      }, (error: Object): void => {
        this.cancellationListeners.delete(cancel);
        reject(XmaxError.from(error));
      });
    });
  }

  /**
   * 等待指定时长；操作失效时提前以取消错误结束。
   *
   * @param milliseconds 等待时长，单位毫秒。
   * @returns 操作完成时兑现的 Promise。
   */
  async delay(milliseconds: number): Promise<void> {
    let timer: number = -1;
    const delay = new Promise<void>((resolve: () => void): void => {
      timer = setTimeout(resolve, milliseconds);
    });
    try {
      await this.wait(delay);
    } finally {
      clearTimeout(timer);
    }
  }

  /**
   * 创建可由接入方识别的操作取消错误。
   *
   * @returns 错误码为 CANCELLED 的 SDK 错误。
   */
  static cancelledError(): XmaxError {
    return new XmaxError(XmaxErrorCode.CANCELLED, 'Realtime operation was cancelled');
  }
}

/** 保存单次实时操作的所有权、完成通知和关联清理任务。 */
class RealtimeOperation {

  /** 操作身份与执行权限 */
  readonly kind: RealtimeOperationKind;
  readonly token: RealtimeOperationToken;

  /** 完成等待与终止关联 */
  completion: Promise<void> = Promise.resolve();
  termination: RealtimeTermination | null = null;

  /**
   * 创建实时操作记录。
   *
   * @param kind 实时操作或状态原因的类型。
   * @param failureScope 操作失败时的资源清理范围；null 表示由调用处自行回滚。
   * @returns 新建的 RealtimeOperation 实例。
   */
  constructor(kind: RealtimeOperationKind, failureScope: RealtimeTerminationScope | null) {
    this.kind = kind;
    this.token = new RealtimeOperationToken(failureScope);
  }
}

/** 合并并发终止请求，保存清理范围、结束原因和资源释放进度。 */
class RealtimeTermination {

  /** 终止原因与资源范围 */
  reason: RealtimeReason | undefined;
  target: RealtimeTerminationScope;
  error: XmaxError | undefined;
  sessionId: string | undefined;

  /** 清理版本与待结束操作 */
  revision: number = 0;
  readonly operations: Set<RealtimeOperation> = new Set();
  promise: Promise<void> = Promise.resolve();

  /**
   * 创建资源终止任务。
   *
   * @param target 请求终止的资源范围。
   * @param error 当前操作失败或终止的原因。
   * @returns 新建的 RealtimeTermination 实例。
   */
  constructor(target: RealtimeTerminationScope, error?: XmaxError) {
    this.target = target;
    this.error = error;
  }
}

/** 在 ArkTS 事件循环中统一管理操作准入、状态提交和分级清理。 */
export class RealtimeCoordinator {

  /** 错误处理与资源清理依赖 */
  private readonly errorManager: XmaxRealtimeErrorManager;
  private readonly cleanup: CleanupHandler;
  /**
   * 查询本地输入是否仍可用，供资源清理后选择最终状态。
   *
   * @returns 本地媒体可用时返回 true。
   */
  private readonly hasLocalMedia: () => boolean;

  /** 业务状态与通知 */
  private state: RealtimeState = new RealtimeState(RealtimeConnectionState.IDLE);
  private stateListener: RealtimeStateListener | null = null;

  /** 互斥操作与终止任务 */
  private activeOperation: RealtimeOperation | null = null;
  private termination: RealtimeTermination | null = null;

  /**
   * 创建实时生命周期协调器。
   *
   * @param errorManager 负责错误转换与通知去重的管理器。
   * @param cleanup 按清理范围释放资源并返回会话标识的异步函数。
   * @param hasLocalMedia 查询本地媒体是否仍可用的函数。
   * @returns 新建的 RealtimeCoordinator 实例。
   */
  constructor(errorManager: XmaxRealtimeErrorManager, cleanup: CleanupHandler,
    hasLocalMedia: () => boolean = (): boolean => false) {
    this.errorManager = errorManager;
    this.cleanup = cleanup;
    this.hasLocalMedia = hasLocalMedia;
  }

  /**
   * 读取实时业务最近一次已提交的状态。
   *
   * @returns 当前实时业务状态。
   */
  get currentState(): RealtimeState {
    return this.state;
  }

  /**
   * 判断是否正在释放全部实时资源。
   *
   * @returns 正在执行完整关闭时返回 true。
   */
  get isClosing(): boolean {
    return this.termination?.target === RealtimeTerminationScope.ALL;
  }

  /**
   * 判断指定类型的操作是否正在执行。
   *
   * @param kind 实时操作或状态原因的类型。
   * @returns 当前正在执行该类型操作时返回 true。
   */
  hasOperation(kind: RealtimeOperationKind): boolean {
    return this.activeOperation?.kind === kind;
  }

  /**
   * 判断是否有任意实时操作正在执行。
   *
   * @returns 存在活动操作时返回 true。
   */
  hasActiveOperation(): boolean {
    return this.activeOperation !== null;
  }

  /**
   * 设置实时状态监听器，并立即通知当前状态；传入 null 清除监听器。
   *
   * @param listener 状态监听器；传入空值时清除监听器。
   * @returns 无返回值。
   */
  setStateListener(listener: RealtimeStateListener | null): void {
    this.stateListener = listener;
    this.notifyStateListener(this.state);
  }

  /**
   * 以互斥方式执行实时操作，并在失败或取消后完成所需清理。
   *
   * @param kind 实时操作或状态原因的类型。
   * @param failureScope 操作失败时的资源清理范围；null 表示由调用处自行回滚。
   * @param body 在操作令牌有效期间执行的操作体。
   * @returns 操作执行结果；忙碌、失败或取消时拒绝的 Promise。
   */
  run<T>(kind: RealtimeOperationKind, failureScope: RealtimeTerminationScope | null,
    body: (token: RealtimeOperationToken) => Promise<T>): Promise<T> {
    if (this.termination !== null || this.activeOperation !== null) {
      return Promise.reject(this.errorManager.handle(new XmaxError(XmaxErrorCode.INVALID_CONFIGURATION,
        'Another realtime operation is in progress; wait for it to finish')));
    }
    const operation = new RealtimeOperation(kind, failureScope);
    this.activeOperation = operation;
    if (this.state.reason !== undefined) {
      this.setState(new RealtimeState(this.state.connectionState, this.state.sessionId, this.state.taskId));
    }
    const execution: Promise<T> = this.execute(body, operation.token);
    // 只等待操作体，不等待包含清理的 run 返回值，避免取消与清理相互等待。
    operation.completion = execution.then((): void => {}, (_error: Object): void => {});
    return this.finishRun(execution, operation);
  }

  /**
   * 自动调档不排队、不报告忙碌错误，也不覆盖用户状态原因。
   *
   * @param body 在操作令牌有效期间执行的操作体。
   * @returns 成功执行配置操作时返回 true；非生成态、忙碌或清理期间返回 false。
   */
  runAdaptiveConfiguration(body: (token: RealtimeOperationToken) => void): boolean {
    if (this.termination !== null || this.activeOperation !== null ||
      this.state.connectionState !== RealtimeConnectionState.GENERATING) { return false; }
    const operation: RealtimeOperation = new RealtimeOperation(RealtimeOperationKind.CONFIGURATION, null);
    this.activeOperation = operation;
    try {
      operation.token.ensureCurrent();
      body(operation.token);
      operation.token.ensureCurrent();
      return true;
    } finally {
      this.finish(operation);
    }
  }

  /**
   * 在确认操作有效后执行异步操作体。
   *
   * @param body 在操作令牌有效期间执行的操作体。
   * @param token 用于校验操作所有权和处理取消的令牌。
   * @returns 操作体返回结果的 Promise。
   */
  private async execute<T>(body: (token: RealtimeOperationToken) => Promise<T>,
    token: RealtimeOperationToken): Promise<T> {
    token.ensureCurrent();
    return await body(token);
  }

  /**
   * 仅允许当前有效操作提交状态，并在通知监听器后再次验证操作有效性。
   *
   * @param next 需要提交的新状态或档位。
   * @param token 用于校验操作所有权和处理取消的令牌。
   * @returns 无返回值。
   */
  commit(next: RealtimeState, token: RealtimeOperationToken): void {
    token.ensureCurrent();
    if (this.activeOperation?.token !== token) {
      throw RealtimeOperationToken.cancelledError();
    }
    this.setState(next);
    // 监听器可以同步发起停止/关闭，后续逻辑不得继续使用刚才的有效性判断。
    token.ensureCurrent();
  }

  /**
   * 只接受当前媒体的就绪通知，迟到通知不能覆盖正在连接或关闭的状态。
   *
   * @param isCurrent 判断通知是否仍属于当前媒体的函数。
   * @returns 无返回值。
   */
  localPreviewDidBecomeReady(isCurrent: () => boolean): void {
    if (this.termination === null && this.state.connectionState === RealtimeConnectionState.PREPARING && isCurrent()) {
      this.setState(new RealtimeState(RealtimeConnectionState.READY));
    }
  }

  /**
   * 终止指定范围内的操作并等待资源清理完成。
   *
   * @param target 请求终止的资源范围。
   * @param reason 操作结束原因或平台告警原因。
   * @returns 操作完成时兑现的 Promise。
   */
  terminate(target: RealtimeTerminationScope, reason: RealtimeReason = RealtimeReason.NORMAL): Promise<void> {
    return this.requestTermination(target, undefined, reason).promise;
  }

  /**
   * 因故障终止指定范围的操作，并将错误写入最终状态。
   *
   * @param error 当前操作失败或终止的原因。
   * @param target 请求终止的资源范围。
   * @returns 操作完成时兑现的 Promise。
   */
  terminateWithError(error: XmaxError, target: RealtimeTerminationScope): Promise<void> {
    // 断开期间迟到的连接错误不覆盖主动结束原因；本地媒体故障仍须扩大清理范围。
    if (this.termination !== null && target !== RealtimeTerminationScope.ALL) {
      return Promise.resolve();
    }
    return this.requestTermination(target, error).promise;
  }

  /**
   * 汇总操作结果并完成失败清理，避免取消后的结果继续提交。
   *
   * @param execution 当前操作体的执行结果 Promise。
   * @param operation 需要完成或清理的实时操作记录。
   * @returns 操作结果；失败或取消时在清理完成后拒绝的 Promise。
   */
  private async finishRun<T>(execution: Promise<T>, operation: RealtimeOperation): Promise<T> {
    try {
      const value: T = await execution;
      operation.token.ensureCurrent();
      this.finish(operation);
      return value;
    } catch (error) {
      const resolved: XmaxError = XmaxError.from(error);
      let pending: RealtimeTermination | null = operation.termination;
      const cancelled: boolean = !operation.token.isCurrent ||
        resolved.code === XmaxErrorCode.CANCELLED || pending !== null;
      if (cancelled) {
        if (pending === null && operation.token.failureScope !== null) {
          pending = this.requestTermination(operation.token.failureScope);
        }
      } else if (operation.token.failureScope !== null) {
        pending = this.requestTermination(operation.token.failureScope, resolved);
      }
      if (pending !== null) {
        await pending.promise;
      }
      this.finish(operation);
      if (pending === null) {
        // 本地创建自行回滚；先释放操作所有权，再通知无 reason 的 IDLE，允许监听器重试。
        if (operation.kind === RealtimeOperationKind.MEDIA &&
          this.state.connectionState === RealtimeConnectionState.PREPARING) {
          this.setState(new RealtimeState(RealtimeConnectionState.IDLE));
        }
        if (!cancelled) {
          this.errorManager.handle(resolved);
        }
      }
      if (operation.token.terminalError !== null) {
        throw operation.token.terminalError;
      }
      if (pending !== null || cancelled) {
        throw RealtimeOperationToken.cancelledError();
      }
      throw resolved;
    }
  }

  /**
   * 合并终止请求并取消受影响的操作，复用同一个清理任务。
   *
   * @param target 请求终止的资源范围。
   * @param error 当前操作失败或终止的原因。
   * @param reason 操作结束原因或平台告警原因。
   * @returns 包含合并后清理范围的终止任务。
   */
  private requestTermination(target: RealtimeTerminationScope,
    error?: XmaxError, reason?: RealtimeReason): RealtimeTermination {
    const beginsDisconnection: boolean = this.termination === null;
    let pending: RealtimeTermination;
    if (this.termination !== null) {
      pending = this.termination;
      if (target > pending.target) {
        pending.target = target;
        pending.revision++;
      }
      if (pending.error === undefined && error !== undefined) {
        pending.error = error;
        pending.revision++;
      }
    } else {
      pending = new RealtimeTermination(target, error);
      this.termination = pending;
      // 先登记共享任务，再运行清理及同步状态回调。
      pending.promise = Promise.resolve().then((): Promise<void> => this.performTermination(pending));
    }
    pending.reason = pending.error !== undefined ? RealtimeReason.failure(pending.error) :
      pending.reason ?? reason ?? RealtimeReason.NORMAL;
    const active: RealtimeOperation | null = this.activeOperation;
    if (active !== null && this.affects(pending.target, active.kind)) {
      if (active.termination !== pending) {
        active.termination = pending;
        pending.operations.add(active);
      }
      active.token.invalidate(pending.error);
    }
    if (beginsDisconnection) {
      this.setState(new RealtimeState(RealtimeConnectionState.DISCONNECTING, this.state.sessionId));
    }
    return pending;
  }

  /**
   * 等待受影响操作退出，完成分级资源清理并提交最终状态。
   *
   * @param pending 合并后的终止请求及其资源清理状态。
   * @returns 操作完成时兑现的 Promise。
   */
  private async performTermination(pending: RealtimeTermination): Promise<void> {
    while (true) {
      const operations: RealtimeOperation[] = Array.from(pending.operations);
      pending.operations.clear();
      for (const operation of operations) {
        await operation.completion;
      }
      const revision: number = pending.revision;
      const scope: RealtimeTerminationScope = pending.target;
      try {
        const sessionId: string | undefined = await this.cleanup(scope, this.state.taskId ?? '');
        pending.sessionId = sessionId ?? pending.sessionId;
      } catch (error) {
        XmaxLogger.error(`${XmaxLogger.localized("实时资源清理失败 (Realtime Cleanup Failed)\n└─ 原因：", "实时资源清理失败 (Realtime Cleanup Failed)\n└─ Reason: ")}${XmaxError.from(error).message}`, 'Realtime');
      }
      if (pending.revision !== revision || pending.operations.size > 0) {
        continue;
      }
      const next: RealtimeState = this.resolveFinalState(pending);
      if (pending.error !== undefined) {
        this.errorManager.handle(pending.error);
      }
      if (this.activeOperation?.termination === pending) {
        this.finish(this.activeOperation);
      }
      this.termination = null;
      this.setState(next);
      return;
    }
  }

  /**
   * 根据清理范围和本地媒体可用性计算结束状态。
   *
   * @param pending 合并后的终止请求及其资源清理状态。
   * @returns 清理完成后应通知的实时状态。
   */
  private resolveFinalState(pending: RealtimeTermination): RealtimeState {
    const connectionState: RealtimeConnectionState = pending.target === RealtimeTerminationScope.ALL ?
      RealtimeConnectionState.IDLE : this.hasLocalMedia() ?
        RealtimeConnectionState.READY : RealtimeConnectionState.IDLE;
    return new RealtimeState(connectionState, pending.sessionId ?? this.state.sessionId, undefined, pending.reason);
  }

  /**
   * 判断给定清理范围是否会终止指定类型的操作。
   *
   * @param scope 需要释放资源的清理范围。
   * @param kind 实时操作或状态原因的类型。
   * @returns 该类操作受清理影响时返回 true。
   */
  private affects(scope: RealtimeTerminationScope, kind: RealtimeOperationKind): boolean {
    if (scope === RealtimeTerminationScope.ALL) {
      return true;
    }
    return kind !== RealtimeOperationKind.MEDIA &&
      kind !== RealtimeOperationKind.PLAYBACK;
  }

  /**
   * 释放当前操作的执行权限，并使其令牌失效。
   *
   * @param operation 需要完成或清理的实时操作记录。
   * @returns 无返回值。
   */
  private finish(operation: RealtimeOperation): void {
    if (this.activeOperation === operation) {
      this.activeOperation = null;
    }
    operation.token.invalidate();
  }

  /**
   * 保存有变化的实时状态并通知监听器。
   *
   * @param next 需要提交的新状态或档位。
   * @returns 无返回值。
   */
  private setState(next: RealtimeState): void {
    if (this.state.connectionState === next.connectionState && this.state.sessionId === next.sessionId &&
      this.state.taskId === next.taskId && this.state.reason?.kind === next.reason?.kind && this.state.reason?.error === next.reason?.error) {
      return;
    }
    this.state = next;
    this.notifyStateListener(next);
  }

  /**
   * 通知状态监听器，并隔离监听器抛出的异常。
   *
   * @param state 需要通知的业务状态。
   * @returns 无返回值。
   */
  private notifyStateListener(state: RealtimeState): void {
    try {
      this.stateListener?.(state);
    } catch (error) {
      XmaxLogger.error(`${XmaxLogger.localized("实时状态监听器执行失败 (Realtime State Listener Failed)\n└─ 原因：", "实时状态监听器执行失败 (Realtime State Listener Failed)\n└─ Reason: ")}${XmaxError.from(error).message}`, 'Realtime');
    }
  }
}
