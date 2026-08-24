import { resolveStateTarget } from '../../foundation/state/StateTargetResolver';
import { RealtimeVideoTrack } from '../../service/realtime/RealtimeVideoTrack';
import { TrajectoryBinding } from './TrajectoryBinding';

export class TrajectoryRegistry {
  private static readonly bindings: Map<RealtimeVideoTrack, TrajectoryBinding> = new Map();

  static register(
    track: RealtimeVideoTrack,
    binding: TrajectoryBinding
  ): void {
    TrajectoryRegistry.bindings.set(resolveStateTarget(track), binding);
  }

  static unregister(track: RealtimeVideoTrack): void {
    TrajectoryRegistry.bindings.delete(resolveStateTarget(track));
  }

  static binding(track: RealtimeVideoTrack): TrajectoryBinding | null {
    return TrajectoryRegistry.bindings.get(resolveStateTarget(track)) ?? null;
  }
}
