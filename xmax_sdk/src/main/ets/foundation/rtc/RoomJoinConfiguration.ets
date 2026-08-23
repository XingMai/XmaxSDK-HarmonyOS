export class RoomJoinConfiguration {
  readonly roomId: string;
  readonly userId: string;
  readonly token: string;

  constructor(
    roomId: string,
    userId: string,
    token: string
  ) {
    this.roomId = roomId;
    this.userId = userId;
    this.token = token;
  }
}
