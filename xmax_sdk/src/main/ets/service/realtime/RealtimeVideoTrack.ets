import { CameraPosition } from '../../foundation/media/camera/CameraPosition';
import { RealtimeVideoFormat } from './RealtimeVideoFormat';

export class RealtimeVideoTrack {
  readonly id: string;
  videoFormat?: RealtimeVideoFormat;
  position?: CameraPosition;

  constructor(
    id: string,
    videoFormat?: RealtimeVideoFormat,
    position?: CameraPosition
  ) {
    this.id = id;
    this.videoFormat = videoFormat;
    this.position = position;
  }
}
