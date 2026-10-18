import { EncodingBitratePolicy, VideoBitrateBudget } from '../encoding/EncodingBitratePolicy';
import { ImageSize } from '../../service/media/ImageSize';
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
  detection: boolean;
  face_replace: boolean;
  target_size?: number[];
  min_bitrate?: number;
  max_bitrate?: number;
  padding?: string;

  constructor(
    videoFormat: RealtimeVideoFormat,
    context: RealtimeContext,
    faceRestoration: boolean,
    targetSize?: ImageSize,
    paddingContain: boolean = false
  ) {
    this.size = [videoFormat.width, videoFormat.height];
    this.prompt = context.prompt;
    if (context.referencePath !== undefined) {
      this.ref_image_path = context.referencePath;
    }
    this.detection = context.faceDetection ?? false;
    this.face_replace = faceRestoration;
    this.target_size = targetSize === undefined ? undefined : [targetSize.width, targetSize.height];
    this.padding = paddingContain ? 'contain' : undefined;
    if (targetSize !== undefined) {
      const budget: TargetSizeParameters = new TargetSizeParameters(targetSize);
      this.min_bitrate = budget.min_bitrate;
      this.max_bitrate = budget.max_bitrate;
    }
  }
}

class TargetSizeParameters {
  readonly target_size: number[];
  readonly min_bitrate: number = 100;
  readonly max_bitrate: number;
  constructor(size: ImageSize) {
    const budget: VideoBitrateBudget = EncodingBitratePolicy.resolve(new RealtimeVideoFormat(size.width, size.height, 24));
    this.target_size = [size.width, size.height];
    this.max_bitrate = Math.min(10000, budget.maximum);
  }
}

class ChangeTargetSizeRoomEvent extends RuntimeRoomEvent {
  readonly event: string = 'change_target_size';
  readonly user_id: string;
  readonly uid: string;
  readonly params: TargetSizeParameters;
  constructor(userId: string, taskId: string, size: ImageSize) {
    super();
    this.user_id = userId;
    this.uid = taskId;
    this.params = new TargetSizeParameters(size);
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
    context: RealtimeContext,
    faceRestoration: boolean,
    targetSize?: ImageSize,
    paddingContain: boolean = false
  ) {
    super();
    this.params = new GenerationParameters(videoFormat, context, faceRestoration, targetSize, paddingContain);
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
    context: RealtimeContext,
    faceRestoration: boolean,
    targetSize?: ImageSize,
    paddingContain: boolean = false
  ) {
    super();
    this.params = new GenerationParameters(videoFormat, context, faceRestoration, targetSize, paddingContain);
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
  static changeTargetSize(userId: string, taskId: string, size: ImageSize): string {
    return JSON.stringify(new ChangeTargetSizeRoomEvent(userId, taskId, size));
  }

  static start(
    userId: string,
    taskId: string,
    videoFormat: RealtimeVideoFormat,
    context: RealtimeContext,
    faceRestoration: boolean = false,
    targetSize?: ImageSize,
    paddingContain: boolean = false
  ): string {
    return JSON.stringify(new StartRoomEvent(userId, taskId, videoFormat, context, faceRestoration, targetSize, paddingContain));
  }

  static changeCondition(
    userId: string,
    taskId: string,
    videoFormat: RealtimeVideoFormat,
    context: RealtimeContext,
    faceRestoration: boolean = false,
    targetSize?: ImageSize,
    paddingContain: boolean = false
  ): string {
    return JSON.stringify(new ChangeConditionRoomEvent(
      userId,
      taskId,
      videoFormat,
      context,
      faceRestoration,
      targetSize,
      paddingContain
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
