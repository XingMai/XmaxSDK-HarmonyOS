import { RealtimeVideoTrack } from '../../service/realtime/RealtimeVideoTrack';
import { TrajectoryBinding } from './TrajectoryBinding';

export class TrajectoryRegistry {
  private static readonly bindings: Map<RealtimeVideoTrack, TrajectoryBinding> = new Map();

  static register(
    track: RealtimeVideoTrack,
    binding: TrajectoryBinding
  ): void {
    TrajectoryRegistry.bindings.set(RealtimeVideoTrack.resolve(track), binding);
  }

  static unregister(track: RealtimeVideoTrack): void {
    TrajectoryRegistry.bindings.delete(RealtimeVideoTrack.resolve(track));
  }

  static binding(track: RealtimeVideoTrack): TrajectoryBinding | null {
    return TrajectoryRegistry.bindings.get(RealtimeVideoTrack.resolve(track)) ?? null;
  }
}
