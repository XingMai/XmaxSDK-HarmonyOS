//
//  RealtimeState.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { XmaxError } from '../../foundation/errors/XmaxError';

/**
 * A realtime lifecycle phase from local preparation through connection, generation, and
 * disconnection.
 */
export enum RealtimeConnectionState {

  /** No local media stream is available. */
  IDLE = 'Idle',

  /** Local media is preparing; camera input also awaits capture and preview binding. */
  PREPARING = 'Preparing',

  /** Local media is ready for preview, connection, and generation. */
  READY = 'Ready',

  /** A server session is being created and local media connected and published. */
  CONNECTING = 'Connecting',

  /** The realtime connection is open without an active generation task. */
  CONNECTED = 'Connected',

  /** The realtime connection is generating. */
  GENERATING = 'Generating',

  /** Connection and generation resources are being released. */
  DISCONNECTING = 'Disconnecting'
}

/** A state transition reason: normal completion, orientation change, or failure. */
export enum RealtimeReasonKind {

  /** An explicit stop or normal resource release. */
  NORMAL = 'Normal',

  /** An orientation change requiring generation reconfiguration. */
  ORIENTATION_CHANGED = 'OrientationChanged',

  /** A lifecycle failure retaining its SDK error. */
  FAILURE = 'Failure'
}

/** The reason for entering a state, retaining the original failure if present. */
export class RealtimeReason {

  /** An explicit stop or normal resource release. */
  static readonly NORMAL: RealtimeReason = new RealtimeReason(RealtimeReasonKind.NORMAL);

  /** An orientation change requiring generation reconfiguration. */
  static readonly ORIENTATION_CHANGED: RealtimeReason = new RealtimeReason(RealtimeReasonKind.ORIENTATION_CHANGED);

  /** The reason for this state transition. */
  readonly kind: RealtimeReasonKind;

  /** The failure associated with this operation or result. */
  readonly error?: XmaxError;

  /** Creates a realtime state reason. */
  private constructor(
    kind: RealtimeReasonKind,
    error?: XmaxError
  ) {
    this.kind = kind;
    this.error = error;
  }

  /**
   * Creates a state reason retaining an error.
   *
   * @param error The original SDK error retained in the state reason.
   *
   * @returns The failure reason with the original SDK error.
   */
  static failure(
    error: XmaxError
  ): RealtimeReason {
    return new RealtimeReason(
      RealtimeReasonKind.FAILURE,
      error
    );
  }
}

/** A lifecycle snapshot whose reason is cleared when a new operation begins normally. */
export class RealtimeState {

  /** The current realtime lifecycle phase. */
  readonly connectionState: RealtimeConnectionState;

  /** The server session identifier. */
  readonly sessionId?: string;

  /** The generation task identifier. */
  readonly taskId?: string;

  /** The reason for terminating this lifecycle. */
  readonly reason?: RealtimeReason;

  /** Creates a realtime state snapshot. */
  constructor(
    connectionState: RealtimeConnectionState,
    sessionId?: string,
    taskId?: string,
    reason?: RealtimeReason
  ) {
    this.connectionState = connectionState;
    this.sessionId = sessionId;
    this.taskId = taskId;
    this.reason = reason;
  }
}

/**
 * Receives realtime state and transition reason changes.
 *
 * @param state The lifecycle or playback state to deliver.
 */
export type RealtimeStateListener = (
  state: RealtimeState
) => void;
