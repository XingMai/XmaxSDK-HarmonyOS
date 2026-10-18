//
//  RealtimeState.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { XmaxError } from '../../foundation/errors/XmaxError';

/** 标识实时业务从本地准备、连接到生成和断开的生命周期阶段。 */
export enum RealtimeConnectionState {
  IDLE = 'Idle',
  PREPARING = 'Preparing',
  READY = 'Ready',
  CONNECTING = 'Connecting',
  CONNECTED = 'Connected',
  GENERATING = 'Generating',
  DISCONNECTING = 'Disconnecting'
}

/** 区分正常结束、方向变化和故障等状态变更原因。 */
export enum RealtimeReasonKind {
  NORMAL = 'Normal',
  ORIENTATION_CHANGED = 'OrientationChanged',
  FAILURE = 'Failure'
}

/** 进入当前状态的原因；失败原因保留原始错误。 */
export class RealtimeReason {

  /** 常用状态原因 */
  static readonly NORMAL: RealtimeReason = new RealtimeReason(RealtimeReasonKind.NORMAL);
  static readonly ORIENTATION_CHANGED: RealtimeReason = new RealtimeReason(RealtimeReasonKind.ORIENTATION_CHANGED);

  /** 具体原因与关联错误 */
  readonly kind: RealtimeReasonKind;
  readonly error?: XmaxError;

  /**
   * 创建实时状态变更原因。
   *
   * @param kind 实时操作或状态原因的类型。
   * @param error 当前操作失败或终止的原因。
   * @returns 新建的 RealtimeReason 实例。
   */
  private constructor(kind: RealtimeReasonKind, error?: XmaxError) {
    this.kind = kind;
    this.error = error;
  }

  /**
   * 创建携带错误的实时状态变更原因。
   *
   * @param error 当前操作失败或终止的原因。
   * @returns 类型为错误且保留原始 SDK 错误的状态原因。
   */
  static failure(error: XmaxError): RealtimeReason {
    return new RealtimeReason(RealtimeReasonKind.FAILURE, error);
  }
}

/** 当前生命周期状态；正常开始新操作时清空 reason。 */
export class RealtimeState {

  /** 连接阶段 */
  readonly connectionState: RealtimeConnectionState;

  /** 服务会话与生成任务 */
  readonly sessionId?: string;
  readonly taskId?: string;

  /** 状态变更原因 */
  readonly reason?: RealtimeReason;

  /**
   * 创建实时业务状态快照。
   *
   * @param connectionState 实时业务所处的生命周期阶段。
   * @param sessionId 服务端实时会话标识。
   * @param taskId 当前生成任务标识。
   * @param reason 操作结束原因或平台告警原因。
   * @returns 新建的 RealtimeState 实例。
   */
  constructor(connectionState: RealtimeConnectionState, sessionId?: string,
    taskId?: string, reason?: RealtimeReason) {
    this.connectionState = connectionState;
    this.sessionId = sessionId;
    this.taskId = taskId;
    this.reason = reason;
  }
}

/**
 * 接收实时业务当前状态和状态变更原因的回调。
 *
 * @param state 需要通知的业务状态。
 * @returns 无返回值。
 */
export type RealtimeStateListener = (state: RealtimeState) => void;
