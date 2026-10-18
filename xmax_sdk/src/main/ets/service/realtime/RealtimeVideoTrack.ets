//
//  RealtimeVideoTrack.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { CameraPosition } from '../../foundation/media/camera/CameraPosition';
import { resolveStateTarget } from '../../foundation/state/StateTargetResolver';
import { RealtimeVideoFormat } from './RealtimeVideoFormat';

/** 保存视频轨道可更新的格式、摄像头位置和方向通知能力。 */
class RealtimeVideoTrackMetadata {

  /** 可更新的轨道规格与位置 */
  videoFormat?: RealtimeVideoFormat;
  position?: CameraPosition;

  /** 布局方向与变更通知 */
  isLandscape?: boolean;
  /**
   * 通知本地轨道布局方向变化，供生成配置更新。
   *
   * @returns 无返回值。
   */
  orientationChangeHandler?: () => void;

  /**
   * 创建视频轨道元数据。
   *
   * @param videoFormat 媒体输出或传输所需的视频规格。
   * @param position 使用的摄像头位置。
   * @returns 新建的 RealtimeVideoTrackMetadata 实例。
   */
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

/** 可供 SDK 视频视图展示的轨道句柄；使用 SDK 返回的实例绑定视图。 */
export class RealtimeVideoTrack {

  /** 公开轨道身份 */
  readonly id: string;

  /** 原始轨道句柄定位 */
  /**
   * 定位 SDK 管理的原始轨道句柄，供状态代理复制后恢复绑定。
   *
   * @returns SDK 管理的原始轨道实例。
   */
  private readonly originalTrack: () => RealtimeVideoTrack;

  /**
   * 取得视频轨道的原始句柄，供视图状态对象转换后保持绑定一致。
   *
   * @param track SDK 返回的视频轨道句柄。
   * @returns SDK 管理的原始视频轨道句柄。
   * @internal 将 ArkUI 代理或属性副本还原为原始轨道。
   */
  static resolve(track: RealtimeVideoTrack): RealtimeVideoTrack {
    return resolveStateTarget(track).originalTrack();
  }

  /**
   * 读取轨道最近一次同步的视频格式。
   *
   * @returns 当前视频格式；轨道没有元数据时返回 undefined。
   */
  get videoFormat(): RealtimeVideoFormat | undefined {
    return metadataByTrack.get(RealtimeVideoTrack.resolve(this))?.videoFormat;
  }

  /**
   * 读取轨道对应的摄像头位置。
   *
   * @returns 前置或后置位置；非摄像头轨道时返回 undefined。
   */
  get position(): CameraPosition | undefined {
    return metadataByTrack.get(RealtimeVideoTrack.resolve(this))?.position;
  }

  /**
   * 创建视频轨道句柄。
   *
   * @param id 当前资源的唯一标识。
   * @param videoFormat 媒体输出或传输所需的视频规格。
   * @param position 使用的摄像头位置。
   * @returns 新建的 RealtimeVideoTrack 实例。
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
      new RealtimeVideoTrackMetadata(videoFormat, position)
    );
  }
}

/**
 * 仅供 SDK 内部同步本地相机轨道位置。
 *
 * @param track SDK 返回的视频轨道句柄。
 * @param position 使用的摄像头位置。
 * @returns 无返回值。
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
 * 仅供 SDK 内部同步相机转屏后的实际视频规格。
 *
 * @param track SDK 返回的视频轨道句柄。
 * @param format 需要使用的视频格式。
 * @returns 无返回值。
 */
export function updateRealtimeVideoTrackFormat(track: RealtimeVideoTrack, format: RealtimeVideoFormat): void {
  const metadata: RealtimeVideoTrackMetadata | undefined = metadataByTrack.get(RealtimeVideoTrack.resolve(track));
  if (metadata !== undefined) {
    metadata.videoFormat = format;
  }
}

/**
 * 仅供 SDK 为本地轨道注册窗口方向变化处理。
 *
 * @param track SDK 返回的视频轨道句柄。
 * @param handler 处理状态通知或媒体结果的回调。
 * @returns 无返回值。
 */
export function setRealtimeVideoTrackOrientationHandler(track: RealtimeVideoTrack,
  handler?: () => void): void {
  const metadata = metadataByTrack.get(RealtimeVideoTrack.resolve(track));
  if (metadata !== undefined) {
    metadata.orientationChangeHandler = handler;
    metadata.isLandscape = undefined;
  }
}

/**
 * 首次绑定只记录方向；同一轨道的多个视图共享方向，重复事件不再触发。
 *
 * @param track SDK 返回的视频轨道句柄。
 * @param isLandscape 当前显示是否为横向布局。
 * @param notify 是否通知已注册的方向变化处理函数。
 * @returns 无返回值。
 */
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
