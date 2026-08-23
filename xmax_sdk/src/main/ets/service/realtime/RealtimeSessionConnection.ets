export class RealtimeSessionConnection {
  readonly roomId: string;
  readonly userId: string;
  readonly token: string;
  readonly botName?: string;

  constructor(
    roomId: string,
    userId: string,
    token: string,
    botName?: string
  ) {
    this.roomId = roomId;
    this.userId = userId;
    this.token = token;
    this.botName = botName;
  }
}
