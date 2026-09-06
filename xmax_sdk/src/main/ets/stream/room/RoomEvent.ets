import { RuntimeInfo, RuntimeInfoPayload } from '../../foundation/runtime/RuntimeInfo';
import { RealtimeContext } from '../../service/realtime/RealtimeContext';
import { RealtimePoint } from '../../service/realtime/RealtimePoint';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';

const GENERATION_MODEL: string = 'default';

/** 所有房间事件统一携带顶层 runtime，不改变原有业务字段。 */
class RuntimeRoomEvent {
  readonly runtime: RuntimeInfoPayload = RuntimeInfo.current.toPayload();
}

class GenerationParameters {
  model: string = GENERATION_MODEL;
  size: number[];
  prompt: string;
  ref_image_path?: string;

  constructor(
    videoFormat: RealtimeVideoFormat,
    context: RealtimeContext
  ) {
    this.size = [videoFormat.width, videoFormat.height];
    this.prompt = context.prompt;
    if (context.referencePath !== undefined) {
      this.ref_image_path = context.referencePath;
    }
  }
}

class StartRoomEvent extends RuntimeRoomEvent {
  event: string = 'start';
  params: GenerationParameters;
  user_id: string;
  uid: string;

  constructor(
    userId: string,
    taskId: string,
    videoFormat: RealtimeVideoFormat,
    context: RealtimeContext
  ) {
    super();
    this.params = new GenerationParameters(videoFormat, context);
    this.user_id = userId;
    this.uid = taskId;
  }
}

class ChangeConditionRoomEvent extends RuntimeRoomEvent {
  event: string = 'change_condition';
  params: GenerationParameters;
  user_id: string;
  uid: string;

  constructor(
    userId: string,
    taskId: string,
    videoFormat: RealtimeVideoFormat,
    context: RealtimeContext
  ) {
    super();
    this.params = new GenerationParameters(videoFormat, context);
    this.user_id = userId;
    this.uid = taskId;
  }
}

class StopRoomEvent extends RuntimeRoomEvent {
  event: string = 'stop';
  user_id: string;
  uid: string;

  constructor(
    userId: string,
    taskId: string
  ) {
    super();
    this.user_id = userId;
    this.uid = taskId;
  }
}

class TracksRoomEvent extends RuntimeRoomEvent {
  event: string = 'tracks';
  tracks: number[][];
  user_id: string;
  uid: string;

  constructor(
    userId: string,
    taskId: string,
    points: RealtimePoint[]
  ) {
    super();
    this.tracks = points.map((point: RealtimePoint): number[] => [point.x, point.y]);
    this.user_id = userId;
    this.uid = taskId;
  }
}

class HeartbeatRoomEvent extends RuntimeRoomEvent {
  event: string = 'heartbeat';
  user_id: string;

  constructor(userId: string) {
    super();
    this.user_id = userId;
  }
}

export class RoomEvent {
  static start(
    userId: string,
    taskId: string,
    videoFormat: RealtimeVideoFormat,
    context: RealtimeContext
  ): string {
    return JSON.stringify(new StartRoomEvent(userId, taskId, videoFormat, context));
  }

  static changeCondition(
    userId: string,
    taskId: string,
    videoFormat: RealtimeVideoFormat,
    context: RealtimeContext
  ): string {
    return JSON.stringify(new ChangeConditionRoomEvent(
      userId,
      taskId,
      videoFormat,
      context
    ));
  }

  static stop(
    userId: string,
    taskId: string
  ): string {
    return JSON.stringify(new StopRoomEvent(userId, taskId));
  }

  static tracks(
    userId: string,
    taskId: string,
    points: RealtimePoint[]
  ): string {
    return JSON.stringify(new TracksRoomEvent(
      userId,
      taskId,
      points
    ));
  }

  static heartbeat(userId: string): string {
    return JSON.stringify(new HeartbeatRoomEvent(userId));
  }
}
