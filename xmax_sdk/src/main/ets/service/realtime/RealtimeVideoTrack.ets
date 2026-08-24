import { CameraPosition } from '../../foundation/media/camera/CameraPosition';
import { RealtimeVideoFormat } from './RealtimeVideoFormat';

class RealtimeVideoTrackMetadata {
  videoFormat?: RealtimeVideoFormat;
  position?: CameraPosition;

  constructor(
    videoFormat?: RealtimeVideoFormat,
    position?: CameraPosition
  ) {
    this.videoFormat = videoFormat;
    this.position = position;
  }
}

const metadataByTrack: WeakMap<RealtimeVideoTrack, RealtimeVideoTrackMetadata> =
  new WeakMap<RealtimeVideoTrack, RealtimeVideoTrackMetadata>();

export class RealtimeVideoTrack {
  readonly id: string;

  /** @returns 当前视频轨道使用的视频格式。 */
  get videoFormat(): RealtimeVideoFormat | undefined {
    return metadataByTrack.get(this)?.videoFormat;
  }

  /** @returns 本地相机轨道当前使用的摄像头位置。 */
  get position(): CameraPosition | undefined {
    return metadataByTrack.get(this)?.position;
  }

  constructor(
    id: string,
    videoFormat?: RealtimeVideoFormat,
    position?: CameraPosition
  ) {
    this.id = id;
    metadataByTrack.set(
      this,
      new RealtimeVideoTrackMetadata(videoFormat, position)
    );
  }
}

/** 仅供 SDK 内部同步视频轨道格式。 */
export function updateRealtimeVideoTrackFormat(
  track: RealtimeVideoTrack,
  videoFormat: RealtimeVideoFormat
): void {
  const metadata: RealtimeVideoTrackMetadata | undefined = metadataByTrack.get(track);
  if (metadata !== undefined) {
    metadata.videoFormat = videoFormat;
  }
}

/** 仅供 SDK 内部同步本地相机轨道位置。 */
export function updateRealtimeVideoTrackPosition(
  track: RealtimeVideoTrack,
  position: CameraPosition
): void {
  const metadata: RealtimeVideoTrackMetadata | undefined = metadataByTrack.get(track);
  if (metadata !== undefined) {
    metadata.position = position;
  }
}
