import { CameraPosition } from '../../foundation/media/camera/CameraPosition';
import { resolveStateTarget } from '../../foundation/state/StateTargetResolver';
import { RealtimeVideoFormat } from './RealtimeVideoFormat';

class RealtimeVideoTrackMetadata {
  videoFormat?: RealtimeVideoFormat;
  position?: CameraPosition;
  isLandscape?: boolean;
  orientationChangeHandler?: () => void;

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

/** 仅供 SDK 为本地轨道注册窗口方向变化处理。 */
export function setRealtimeVideoTrackOrientationHandler(track: RealtimeVideoTrack,
  handler?: () => void): void {
  const metadata = metadataByTrack.get(RealtimeVideoTrack.resolve(track));
  if (metadata !== undefined) {
    metadata.orientationChangeHandler = handler;
    metadata.isLandscape = undefined;
  }
}

/** 首次绑定只记录方向；同一轨道的多个视图共享方向，重复事件不再触发。 */
export function updateRealtimeVideoTrackOrientation(track: RealtimeVideoTrack,
  isLandscape: boolean, notify: boolean): void {
  const metadata = metadataByTrack.get(RealtimeVideoTrack.resolve(track));
  if (metadata === undefined) {
    return;
  }
  const changed: boolean = metadata.isLandscape !== undefined && metadata.isLandscape !== isLandscape;
  metadata.isLandscape = isLandscape;
  if (notify && changed) {
    metadata.orientationChangeHandler?.();
  }
}
