import { XmaxError } from '../../foundation/errors/XmaxError';

export enum RealtimeConnectionState {
  IDLE = 'Idle',
  PREPARING = 'Preparing',
  READY = 'Ready',
  CONNECTING = 'Connecting',
  CONNECTED = 'Connected',
  GENERATING = 'Generating',
  DISCONNECTING = 'Disconnecting'
}

export enum RealtimeReasonKind {
  NORMAL = 'Normal',
  ORIENTATION_CHANGED = 'OrientationChanged',
  FAILURE = 'Failure'
}

/** 进入当前状态的原因；失败原因保留原始错误。 */
export class RealtimeReason {
  static readonly NORMAL: RealtimeReason = new RealtimeReason(RealtimeReasonKind.NORMAL);
  static readonly ORIENTATION_CHANGED: RealtimeReason = new RealtimeReason(RealtimeReasonKind.ORIENTATION_CHANGED);
  readonly kind: RealtimeReasonKind;
  readonly error?: XmaxError;

  private constructor(kind: RealtimeReasonKind, error?: XmaxError) {
    this.kind = kind;
    this.error = error;
  }

  static failure(error: XmaxError): RealtimeReason {
    return new RealtimeReason(RealtimeReasonKind.FAILURE, error);
  }
}

/** 当前生命周期状态；正常开始新操作时清空 reason。 */
export class RealtimeState {
  readonly connectionState: RealtimeConnectionState;
  readonly sessionId?: string;
  readonly taskId?: string;
  readonly reason?: RealtimeReason;

  constructor(connectionState: RealtimeConnectionState, sessionId?: string,
    taskId?: string, reason?: RealtimeReason) {
    this.connectionState = connectionState;
    this.sessionId = sessionId;
    this.taskId = taskId;
    this.reason = reason;
  }
}

export type RealtimeStateListener = (state: RealtimeState) => void;
