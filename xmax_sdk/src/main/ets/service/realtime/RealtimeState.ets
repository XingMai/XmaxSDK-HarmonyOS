export enum RealtimeConnectionState {
  IDLE = 'Idle',
  CONNECTING = 'Connecting',
  CONNECTED = 'Connected',
  GENERATING = 'Generating',
  DISCONNECTING = 'Disconnecting',
  DISCONNECTED = 'Disconnected',
  ERROR = 'Error'
}

export enum RealtimeDisconnectionReason {
  NORMAL = 'Normal',
  CAMERA_ORIENTATION_CHANGED = 'CameraOrientationChanged'
}

export class RealtimeState {
  readonly connectionState: RealtimeConnectionState;
  readonly sessionId?: string;
  readonly taskId?: string;
  readonly disconnectionReason?: RealtimeDisconnectionReason;

  constructor(
    connectionState: RealtimeConnectionState,
    sessionId?: string,
    taskId?: string,
    disconnectionReason?: RealtimeDisconnectionReason
  ) {
    this.connectionState = connectionState;
    this.sessionId = sessionId;
    this.taskId = taskId;
    this.disconnectionReason = disconnectionReason;
  }
}

export type RealtimeStateListener = (state: RealtimeState) => void;
