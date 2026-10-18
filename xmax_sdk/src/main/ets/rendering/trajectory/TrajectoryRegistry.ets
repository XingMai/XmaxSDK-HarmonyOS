//
//  TrajectoryRegistry.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { RealtimeVideoTrack } from '../../service/realtime/RealtimeVideoTrack';
import { TrajectoryBinding } from './TrajectoryBinding';

/** 通过视频轨道查找交互绑定，供视频视图启用轨迹交互。 */
export class TrajectoryRegistry {

  /** 轨道到交互资源的弱引用绑定 */
  private static readonly bindings: Map<RealtimeVideoTrack, TrajectoryBinding> = new Map();

  /**
   * 将视频轨道与其绑定资源登记到注册表。
   *
   * @param track SDK 返回的视频轨道句柄。
   * @param binding 需要关联到轨道的资源绑定。
   * @returns 无返回值。
   */
  static register(
    track: RealtimeVideoTrack,
    binding: TrajectoryBinding
  ): void {
    TrajectoryRegistry.bindings.set(RealtimeVideoTrack.resolve(track), binding);
  }

  /**
   * 移除指定视频轨道的资源绑定。
   *
   * @param track SDK 返回的视频轨道句柄。
   * @returns 无返回值。
   */
  static unregister(track: RealtimeVideoTrack): void {
    TrajectoryRegistry.bindings.delete(RealtimeVideoTrack.resolve(track));
  }

  /**
   * 查找视频轨道对应的交互绑定。
   *
   * @param track SDK 返回的视频轨道句柄。
   * @returns 交互绑定；未登记时返回 null。
   */
  static binding(track: RealtimeVideoTrack): TrajectoryBinding | null {
    return TrajectoryRegistry.bindings.get(RealtimeVideoTrack.resolve(track)) ?? null;
  }
}
