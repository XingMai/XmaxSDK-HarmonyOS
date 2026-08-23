import { RealtimeSessionConnection } from './RealtimeSessionConnection';

export class RealtimeSession {
  readonly id: string;
  readonly userId?: string;
  readonly status?: string;
  readonly connection?: RealtimeSessionConnection;
  readonly closeReason?: string;

  constructor(
    id: string,
    userId?: string,
    status?: string,
    connection?: RealtimeSessionConnection,
    closeReason?: string
  ) {
    this.id = id;
    this.userId = userId;
    this.status = status;
    this.connection = connection;
    this.closeReason = closeReason;
  }
}
