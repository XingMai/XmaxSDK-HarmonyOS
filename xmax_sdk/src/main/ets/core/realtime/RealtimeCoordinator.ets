import { XmaxError, XmaxErrorCode } from '../../foundation/errors/XmaxError';
import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import { RealtimeConnectionState, RealtimeReason, RealtimeState, RealtimeStateListener } from '../../service/realtime/RealtimeState';
import { XmaxRealtimeErrorManager } from './XmaxRealtimeErrorManager';

export enum RealtimeOperationKind {
  MEDIA,
  CONNECTION,
  GENERATION,
  CAMERA_SWITCH
}

/** 清理范围由小到大，较大的范围包含较小的范围。 */
export enum RealtimeTerminationScope {
  CONNECTION,
  ALL
}

type CancellationListener = (error: XmaxError) => void;
type CleanupHandler = (scope: RealtimeTerminationScope, taskId: string) => Promise<string | undefined>;

/** 跨异步边界验证操作所有权，并取消不再需要的结果等待。 */
export class RealtimeOperationToken {
  private valid: boolean = true;
  private failure: XmaxError | null = null;
  private readonly cancellationListeners: Set<CancellationListener> = new Set();
  // 校验阶段不清理资源；操作开始修改资源后，显式登记失败时的清理范围。
  private storedFailureScope: RealtimeTerminationScope | null;

  constructor(failureScope: RealtimeTerminationScope | null) {
    this.storedFailureScope = failureScope;
  }

  get isCurrent(): boolean {
    return this.valid;
  }

  get failureScope(): RealtimeTerminationScope | null {
    return this.storedFailureScope;
  }

  get terminalError(): XmaxError | null {
    return this.failure;
  }

  setFailureScope(scope: RealtimeTerminationScope | null): void {
    this.storedFailureScope = scope;
  }

  ensureCurrent(): void {
    if (!this.valid) {
      throw this.failure ?? RealtimeOperationToken.cancelledError();
    }
  }

  invalidate(error?: XmaxError): void {
    if (error !== undefined && this.failure === null) {
      this.failure = error;
    }
    this.valid = false;
    const reason: XmaxError = this.failure ?? RealtimeOperationToken.cancelledError();
    this.cancellationListeners.forEach((listener: CancellationListener): void => listener(reason));
    this.cancellationListeners.clear();
  }

  /** 只用于确认/首帧等等待；修改资源的异步操作仍须等待实际结束再清理。 */
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

  static cancelledError(): XmaxError {
    return new XmaxError(XmaxErrorCode.CANCELLED, 'Realtime operation was cancelled');
  }
}

class RealtimeOperation {
  readonly kind: RealtimeOperationKind;
  readonly token: RealtimeOperationToken;
  completion: Promise<void> = Promise.resolve();
  termination: RealtimeTermination | null = null;

  constructor(kind: RealtimeOperationKind, failureScope: RealtimeTerminationScope | null) {
    this.kind = kind;
    this.token = new RealtimeOperationToken(failureScope);
  }
}

class RealtimeTermination {
  reason: RealtimeReason | undefined;
  target: RealtimeTerminationScope;
  error: XmaxError | undefined;
  sessionId: string | undefined;
  revision: number = 0;
  readonly operations: Set<RealtimeOperation> = new Set();
  promise: Promise<void> = Promise.resolve();

  constructor(target: RealtimeTerminationScope, error?: XmaxError) {
    this.target = target;
    this.error = error;
  }
}

/** 在 ArkTS 事件循环中统一管理操作准入、状态提交和分级清理。 */
export class RealtimeCoordinator {
  private readonly errorManager: XmaxRealtimeErrorManager;
  private readonly cleanup: CleanupHandler;
  private readonly hasLocalMedia: () => boolean;
  private state: RealtimeState = new RealtimeState(RealtimeConnectionState.IDLE);
  private stateListener: RealtimeStateListener | null = null;
  private activeOperation: RealtimeOperation | null = null;
  private termination: RealtimeTermination | null = null;

  constructor(errorManager: XmaxRealtimeErrorManager, cleanup: CleanupHandler,
    hasLocalMedia: () => boolean = (): boolean => false) {
    this.errorManager = errorManager;
    this.cleanup = cleanup;
    this.hasLocalMedia = hasLocalMedia;
  }

  get currentState(): RealtimeState {
    return this.state;
  }

  get isClosing(): boolean {
    return this.termination?.target === RealtimeTerminationScope.ALL;
  }

  hasOperation(kind: RealtimeOperationKind): boolean {
    return this.activeOperation?.kind === kind;
  }

  setStateListener(listener: RealtimeStateListener | null): void {
    this.stateListener = listener;
    this.notifyStateListener(this.state);
  }

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

  private async execute<T>(body: (token: RealtimeOperationToken) => Promise<T>,
    token: RealtimeOperationToken): Promise<T> {
    token.ensureCurrent();
    return await body(token);
  }

  commit(next: RealtimeState, token: RealtimeOperationToken): void {
    token.ensureCurrent();
    if (this.activeOperation?.token !== token) {
      throw RealtimeOperationToken.cancelledError();
    }
    this.setState(next);
    // 监听器可以同步发起停止/关闭，后续逻辑不得继续使用刚才的有效性判断。
    token.ensureCurrent();
  }

  /** 只接受当前媒体的就绪通知，迟到通知不能覆盖正在连接或关闭的状态。 */
  localPreviewDidBecomeReady(isCurrent: () => boolean): void {
    if (this.termination === null && this.state.connectionState === RealtimeConnectionState.PREPARING && isCurrent()) {
      this.setState(new RealtimeState(RealtimeConnectionState.READY));
    }
  }

  terminate(target: RealtimeTerminationScope, reason: RealtimeReason = RealtimeReason.NORMAL): Promise<void> {
    return this.requestTermination(target, undefined, reason).promise;
  }

  terminateWithError(error: XmaxError, target: RealtimeTerminationScope): Promise<void> {
    // 断开期间迟到的连接错误不覆盖主动结束原因；本地媒体故障仍须扩大清理范围。
    if (this.termination !== null && target !== RealtimeTerminationScope.ALL) {
      return Promise.resolve();
    }
    return this.requestTermination(target, error).promise;
  }

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
        XmaxLogger.error(`实时资源清理失败\n└─ 原因：${XmaxError.from(error).message}`, 'Realtime');
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

  private resolveFinalState(pending: RealtimeTermination): RealtimeState {
    const connectionState: RealtimeConnectionState = pending.target === RealtimeTerminationScope.ALL ?
      RealtimeConnectionState.IDLE : this.hasLocalMedia() ?
        RealtimeConnectionState.READY : RealtimeConnectionState.IDLE;
    return new RealtimeState(connectionState, pending.sessionId ?? this.state.sessionId, undefined, pending.reason);
  }

  private affects(scope: RealtimeTerminationScope, kind: RealtimeOperationKind): boolean {
    if (scope === RealtimeTerminationScope.ALL) {
      return true;
    }
    return kind !== RealtimeOperationKind.MEDIA;
  }

  private finish(operation: RealtimeOperation): void {
    if (this.activeOperation === operation) {
      this.activeOperation = null;
    }
    operation.token.invalidate();
  }

  private setState(next: RealtimeState): void {
    if (this.state.connectionState === next.connectionState && this.state.sessionId === next.sessionId &&
      this.state.taskId === next.taskId && this.state.reason?.kind === next.reason?.kind && this.state.reason?.error === next.reason?.error) {
      return;
    }
    this.state = next;
    this.notifyStateListener(next);
  }

  private notifyStateListener(state: RealtimeState): void {
    try {
      this.stateListener?.(state);
    } catch (error) {
      XmaxLogger.error(`实时状态监听器执行失败\n└─ 原因：${XmaxError.from(error).message}`, 'Realtime');
    }
  }
}
