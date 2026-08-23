export enum RealtimeConnectionState {
  IDLE = 'Idle',
  CONNECTING = 'Connecting',
  CONNECTED = 'Connected',
  GENERATING = 'Generating',
  DISCONNECTING = 'Disconnecting',
  DISCONNECTED = 'Disconnected',
  ERROR = 'Error'
}

export class RealtimeState {
  readonly connectionState: RealtimeConnectionState;
  readonly sessionId?: string;
  readonly taskId?: string;

  constructor(
    connectionState: RealtimeConnectionState,
    sessionId?: string,
    taskId?: string
  ) {
    this.connectionState = connectionState;
    this.sessionId = sessionId;
    this.taskId = taskId;
  }
}

export type RealtimeStateListener = (state: RealtimeState) => void;
