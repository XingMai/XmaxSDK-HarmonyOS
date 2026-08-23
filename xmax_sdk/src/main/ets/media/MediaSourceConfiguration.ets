import { RealtimeVideoFormat } from '../service/realtime/RealtimeVideoFormat';

export class MediaSourceConfiguration {
  readonly videoFormat: RealtimeVideoFormat;
  readonly hasAudio: boolean;

  constructor(
    videoFormat: RealtimeVideoFormat,
    hasAudio: boolean
  ) {
    this.videoFormat = videoFormat;
    this.hasAudio = hasAudio;
  }
}
