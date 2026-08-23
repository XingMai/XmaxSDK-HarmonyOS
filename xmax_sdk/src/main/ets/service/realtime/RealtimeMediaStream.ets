import { RealtimeVideoTrack } from './RealtimeVideoTrack';

export class RealtimeMediaStream {
  readonly id: string;
  readonly videoTrack?: RealtimeVideoTrack;

  constructor(
    id: string,
    videoTrack?: RealtimeVideoTrack
  ) {
    this.id = id;
    this.videoTrack = videoTrack;
  }
}
