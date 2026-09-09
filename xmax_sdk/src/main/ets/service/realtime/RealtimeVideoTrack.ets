import { CameraPosition } from '../../foundation/media/camera/CameraPosition';
import { resolveStateTarget } from '../../foundation/state/StateTargetResolver';
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
  // ArkUI V1 @Prop 会复制对象；函数闭包仍指向同一个不透明轨道句柄。
  private readonly originalTrack: () => RealtimeVideoTrack;

  /** @internal 将 ArkUI 代理或属性副本还原为原始轨道。 */
  static resolve(track: RealtimeVideoTrack): RealtimeVideoTrack {
    return resolveStateTarget(track).originalTrack();
  }

  /** @returns 当前视频轨道使用的视频格式。 */
  get videoFormat(): RealtimeVideoFormat | undefined {
    return metadataByTrack.get(RealtimeVideoTrack.resolve(this))?.videoFormat;
  }

  /** @returns 本地相机轨道当前使用的摄像头位置。 */
  get position(): CameraPosition | undefined {
    return metadataByTrack.get(RealtimeVideoTrack.resolve(this))?.position;
  }

  constructor(
    id: string,
    videoFormat?: RealtimeVideoFormat,
    position?: CameraPosition
  ) {
    this.id = id;
    this.originalTrack = (): RealtimeVideoTrack => this;
    metadataByTrack.set(
      this,
      new RealtimeVideoTrackMetadata(videoFormat, position)
    );
  }
}

/** 仅供 SDK 内部同步本地相机轨道位置。 */
export function updateRealtimeVideoTrackPosition(
  track: RealtimeVideoTrack,
  position: CameraPosition
): void {
  const metadata: RealtimeVideoTrackMetadata | undefined =
    metadataByTrack.get(RealtimeVideoTrack.resolve(track));
  if (metadata !== undefined) {
    metadata.position = position;
  }
}

/** 仅供 SDK 内部同步相机转屏后的实际视频规格。 */
export function updateRealtimeVideoTrackFormat(track: RealtimeVideoTrack, format: RealtimeVideoFormat): void {
  const metadata: RealtimeVideoTrackMetadata | undefined = metadataByTrack.get(RealtimeVideoTrack.resolve(track));
  if (metadata !== undefined) {
    metadata.videoFormat = format;
  }
}
