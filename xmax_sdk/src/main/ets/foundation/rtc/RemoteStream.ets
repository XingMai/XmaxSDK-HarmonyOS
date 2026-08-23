export class RemoteStream {
  readonly roomId: string;
  readonly userId: string;

  constructor(
    roomId: string,
    userId: string
  ) {
    this.roomId = roomId;
    this.userId = userId;
  }

  key(): string {
    return `${this.roomId}:${this.userId}`;
  }
}
