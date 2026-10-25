//
//  TrajectoryRegistry.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { RealtimeVideoTrack } from '../../service/realtime/RealtimeVideoTrack';
import { TrajectoryBinding } from './TrajectoryBinding';

/** Finds track interaction bindings for video views. */
export class TrajectoryRegistry {

  /** The weak mappings from original tracks to their resource bindings. */
  private static readonly bindings: Map<RealtimeVideoTrack, TrajectoryBinding> = new Map();

  /**
   * Registers a track and its resource binding.
   *
   * @param track The SDK video track handle.
   * @param binding The resource binding to associate with the track.
   */
  static register(
    track: RealtimeVideoTrack,
    binding: TrajectoryBinding
  ): void {
    TrajectoryRegistry.bindings.set(
      RealtimeVideoTrack.resolve(track),
      binding
    );
  }

  /**
   * Removes a track's resource binding.
   *
   * @param track The SDK video track handle.
   */
  static unregister(
    track: RealtimeVideoTrack
  ): void {
    TrajectoryRegistry.bindings.delete(RealtimeVideoTrack.resolve(track));
  }

  /**
   * Returns the interaction binding for a track.
   *
   * @param track The SDK video track handle.
   *
   * @returns The interaction binding, or null if unregistered.
   */
  static binding(
    track: RealtimeVideoTrack
  ): TrajectoryBinding | null {
    return TrajectoryRegistry.bindings.get(RealtimeVideoTrack.resolve(track)) ?? null;
  }
}
