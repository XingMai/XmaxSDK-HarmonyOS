//
//  RealtimeVideoTrack.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { CameraPosition } from '../../foundation/media/camera/CameraPosition';
import { resolveStateTarget } from '../../foundation/state/StateTargetResolver';
import { RealtimeVideoFormat } from './RealtimeVideoFormat';

/** Mutable track format, camera position, and orientation notification metadata. */
class RealtimeVideoTrackMetadata {

  /** The current video dimensions, frame rate, and encoding settings. */
  videoFormat?: RealtimeVideoFormat;

  /** The track's camera position, absent for non-camera media. */
  position?: CameraPosition;

  /** Whether the bound layout is landscape. */
  isLandscape?: boolean;

  /** Reports local track orientation changes for generation configuration updates. */
  orientationChangeHandler?: () => void;

  /** Creates video track metadata. */
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

/** A track handle for SDK video views. Bind the instance returned by XmaxSDK. */
export class RealtimeVideoTrack {

  /** The video track identifier. */
  readonly id: string;

  /**
   * Finds the SDK-owned track after state management creates proxy copies.
   *
   * @returns The original SDK-owned track instance.
   */
  private readonly originalTrack: () => RealtimeVideoTrack;

  /**
   * Returns the original video track for consistent binding after state-object conversion.
   *
   * @param track The SDK video track handle.
   *
   * @returns The original SDK-owned video track handle.
   * @internal Unwraps ArkUI proxies or property copies into the original track.
   */
  static resolve(
    track: RealtimeVideoTrack
  ): RealtimeVideoTrack {
    return resolveStateTarget(track).originalTrack();
  }

  /** The most recently synchronized track format, or undefined without track metadata. */
  get videoFormat(): RealtimeVideoFormat | undefined {
    return metadataByTrack.get(RealtimeVideoTrack.resolve(this))?.videoFormat;
  }

  /** The track's front or rear camera position, or undefined for non-camera tracks. */
  get position(): CameraPosition | undefined {
    return metadataByTrack.get(RealtimeVideoTrack.resolve(this))?.position;
  }

  /**
   * Creates a video track handle.
   *
   * @param id The resource identifier.
   * @param videoFormat The media output or transport format.
   * @param position The active camera position.
   */
  constructor(
    id: string,
    videoFormat?: RealtimeVideoFormat,
    position?: CameraPosition
  ) {
    this.id = id;
    this.originalTrack = (): RealtimeVideoTrack => this;
    metadataByTrack.set(
      this,
      new RealtimeVideoTrackMetadata(
        videoFormat,
        position
      )
    );
  }
}

/**
 * Updates local camera track position for SDK internals.
 *
 * @param track The SDK video track handle.
 * @param position The active camera position.
 */
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

/**
 * Updates the actual camera format after rotation for SDK internals.
 *
 * @param track The SDK video track handle.
 * @param format The video format to use.
 */
export function updateRealtimeVideoTrackFormat(
  track: RealtimeVideoTrack,
  format: RealtimeVideoFormat
): void {
  const metadata: RealtimeVideoTrackMetadata | undefined = metadataByTrack.get(RealtimeVideoTrack.resolve(track));
  if (metadata !== undefined) {
    metadata.videoFormat = format;
  }
}

/**
 * Registers window orientation changes for a local track.
 *
 * @param track The SDK video track handle.
 * @param handler The state or media result handler.
 */
export function setRealtimeVideoTrackOrientationHandler(
  track: RealtimeVideoTrack,
  handler?: () => void
): void {
  const metadata = metadataByTrack.get(RealtimeVideoTrack.resolve(track));
  if (metadata !== undefined) {
    metadata.orientationChangeHandler = handler;
    metadata.isLandscape = undefined;
  }
}

/**
 * Initial binding records orientation only. Views sharing a track share orientation; duplicate
 * events do not notify again.
 *
 * @param track The SDK video track handle.
 * @param isLandscape Whether the display layout is landscape.
 * @param notify Whether to notify the registered orientation handler.
 */
export function updateRealtimeVideoTrackOrientation(
  track: RealtimeVideoTrack,
  isLandscape: boolean,
  notify: boolean
): void {
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
