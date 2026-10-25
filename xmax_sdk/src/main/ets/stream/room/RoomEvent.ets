//
//  RoomEvent.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { RealtimeGenerationParameters } from '../../service/realtime/RealtimeGenerationOptions';
import { EncodingBitratePolicy, VideoBitrateBudget } from '../encoding/EncodingBitratePolicy';
import { ImageSize } from '../../service/media/ImageSize';
import { RuntimeInfo, RuntimeInfoPayload } from '../../foundation/runtime/RuntimeInfo';
import { RealtimeContext } from '../../service/realtime/RealtimeContext';
import { RealtimePoint } from '../../service/realtime/RealtimePoint';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';

const GENERATION_MODEL: string = 'default';

/** Common runtime fields for room signaling. */
class RuntimeRoomEvent {

  // Signal runtime information

  /** The runtime metadata serialized into room signaling. */
  readonly runtime: RuntimeInfoPayload = RuntimeInfo.current.toPayload();
}

/** Serializable generation canvas, conditions, result dimensions, and bitrate budget. */
class GenerationParameters {

  // Generation canvas and conditions

  /** The model defining media sizing and generation constraints. */
  model: string = GENERATION_MODEL;

  /** The frame dimensions carried by the request. */
  size: number[];

  /** The prompt describing the desired generation result. */
  prompt: string;

  /** The server-accessible reference image path. */
  ref_image_path?: string;

  /** Whether static generation is enabled and its server-accessible image URL. */
  static_generate?: boolean;

  /** The server-accessible static generation image path. */
  static_image_path?: string;

  /** The face detection setting sent to the server. */
  detection: boolean;

  /** Whether to restore the original face in generated output. */
  face_replace: boolean;

  // Result target dimensions and bitrate

  /** The requested result dimensions and bitrate budget. */
  target_size?: number[];

  /** The minimum result bitrate, in kbps. */
  min_bitrate?: number;

  /** The maximum result bitrate, in kbps. */
  max_bitrate?: number;

  // Media aspect ratio and padding policy

  /** The aspect-preserving input padding policy. */
  padding?: string;

  /**
   * Creates generation signal parameters.
   *
   * @param videoFormat The media output or transport format.
   * @param context The prompt, reference image, and face detection configuration.
   * @param faceRestoration Whether to enable face restoration.
   * @param targetSize The optional result stream target dimensions.
   * @param paddingContain Whether to preserve media aspect ratio with server-side padding.
   * @param extraParams The static generation parameters passed internally by the SDK.
   */
  constructor(
    videoFormat: RealtimeVideoFormat,
    context: RealtimeContext,
    faceRestoration: boolean,
    targetSize?: ImageSize,
    paddingContain: boolean = false,
    extraParams?: RealtimeGenerationParameters
  ) {
    this.size = [videoFormat.width, videoFormat.height];
    this.prompt = context.prompt;
    if (context.referencePath !== undefined) {
      this.ref_image_path = context.referencePath;
    }
    this.static_generate = extraParams?.static_generate;
    this.static_image_path = extraParams?.static_image_path;
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

/** Serializable result dimensions and bitrate bounds for server downlink adjustment. */
class TargetSizeParameters {

  // Result stream target dimensions

  /** The requested result dimensions and bitrate budget. */
  readonly target_size: number[];

  // Result stream bitrate bounds

  /** The minimum result bitrate, in kbps. */
  readonly min_bitrate: number = 100;

  /** The maximum result bitrate, in kbps. */
  readonly max_bitrate: number;

  /**
   * Creates result dimensions and bitrate parameters.
   *
   * @param size The requested result stream dimensions, in pixels.
   */
  constructor(
    size: ImageSize
  ) {
    const budget: VideoBitrateBudget = EncodingBitratePolicy.resolve(new RealtimeVideoFormat(
      size.width,
      size.height,
      24
    ));
    this.target_size = [size.width, size.height];
    this.max_bitrate = Math.min(10000, budget.maximum);
  }
}

/** A request to change a task's result dimensions and bitrate. */
class ChangeTargetSizeRoomEvent extends RuntimeRoomEvent {

  // Event routing and task identity

  /** The room signaling event name. */
  readonly event: string = 'change_target_size';

  /** The local room user identifier carried by the signal. */
  readonly user_id: string;

  /** The generation task identifier carried by the signal. */
  readonly uid: string;

  // Result stream target configuration

  /** The generation parameters serialized into the signal. */
  readonly params: TargetSizeParameters;

  /**
   * Creates a result quality change signal.
   *
   * @param userId The RTC user identifier.
   * @param taskId The current generation task identifier.
   * @param size The requested result stream dimensions, in pixels.
   */
  constructor(
    userId: string,
    taskId: string,
    size: ImageSize
  ) {
    super();
    this.user_id = userId;
    this.uid = taskId;
    this.params = new TargetSizeParameters(size);
  }
}

/** A generation start signal with task identity and parameters. */
class StartRoomEvent extends RuntimeRoomEvent {

  // Event type

  /** The room signaling event name. */
  event: string = 'start';

  // Generation configuration

  /** The generation parameters serialized into the signal. */
  params: GenerationParameters;

  // User and task identity

  /** The local room user identifier carried by the signal. */
  user_id: string;

  /** The generation task identifier carried by the signal. */
  uid: string;

  /**
   * Creates a generation start signal.
   *
   * @param userId The RTC user identifier.
   * @param taskId The current generation task identifier.
   * @param videoFormat The media output or transport format.
   * @param context The prompt, reference image, and face detection configuration.
   * @param faceRestoration Whether to enable face restoration.
   * @param targetSize The optional result stream target dimensions.
   * @param paddingContain Whether to preserve media aspect ratio with server-side padding.
   * @param extraParams The static generation parameters passed internally by the SDK.
   */
  constructor(
    userId: string,
    taskId: string,
    videoFormat: RealtimeVideoFormat,
    context: RealtimeContext,
    faceRestoration: boolean,
    targetSize?: ImageSize,
    paddingContain: boolean = false,
    extraParams?: RealtimeGenerationParameters
  ) {
    super();
    this.params = new GenerationParameters(
      videoFormat,
      context,
      faceRestoration,
      targetSize,
      paddingContain,
      extraParams
    );
    this.user_id = userId;
    this.uid = taskId;
  }
}

/** A task signal carrying updated generation conditions. */
class ChangeConditionRoomEvent extends RuntimeRoomEvent {

  // Event type

  /** The room signaling event name. */
  event: string = 'change_condition';

  // Generation conditions

  /** The generation parameters serialized into the signal. */
  params: GenerationParameters;

  // User and task identity

  /** The local room user identifier carried by the signal. */
  user_id: string;

  /** The generation task identifier carried by the signal. */
  uid: string;

  /**
   * Creates a generation condition update signal.
   *
   * @param userId The RTC user identifier.
   * @param taskId The current generation task identifier.
   * @param videoFormat The media output or transport format.
   * @param context The prompt, reference image, and face detection configuration.
   * @param faceRestoration Whether to enable face restoration.
   * @param targetSize The optional result stream target dimensions.
   * @param paddingContain Whether to preserve media aspect ratio with server-side padding.
   * @param extraParams The static generation parameters passed internally by the SDK.
   */
  constructor(
    userId: string,
    taskId: string,
    videoFormat: RealtimeVideoFormat,
    context: RealtimeContext,
    faceRestoration: boolean,
    targetSize?: ImageSize,
    paddingContain: boolean = false,
    extraParams?: RealtimeGenerationParameters
  ) {
    super();
    this.params = new GenerationParameters(
      videoFormat,
      context,
      faceRestoration,
      targetSize,
      paddingContain,
      extraParams
    );
    this.user_id = userId;
    this.uid = taskId;
  }
}

/** A signal requesting termination of a task. */
class StopRoomEvent extends RuntimeRoomEvent {

  // Event type and task identity

  /** The room signaling event name. */
  event: string = 'stop';

  /** The local room user identifier carried by the signal. */
  user_id: string;

  /** The generation task identifier carried by the signal. */
  uid: string;

  /**
   * Creates a generation stop signal.
   *
   * @param userId The RTC user identifier.
   * @param taskId The current generation task identifier.
   */
  constructor(
    userId: string,
    taskId: string
  ) {
    super();
    this.user_id = userId;
    this.uid = taskId;
  }
}

/** A task signal carrying normalized interaction points. */
class TracksRoomEvent extends RuntimeRoomEvent {

  // Event type

  /** The room signaling event name. */
  event: string = 'tracks';

  // Interaction point data

  /** The normalized touch points sent to the generation task. */
  tracks: number[][];

  // User and task identity

  /** The local room user identifier carried by the signal. */
  user_id: string;

  /** The generation task identifier carried by the signal. */
  uid: string;

  /**
   * Creates an interaction trajectory signal.
   *
   * @param userId The RTC user identifier.
   * @param taskId The current generation task identifier.
   * @param points The touch points to submit or draw.
   */
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

/** A heartbeat maintaining room business activity. */
class HeartbeatRoomEvent extends RuntimeRoomEvent {

  // Heartbeat event and user identity

  /** The room signaling event name. */
  event: string = 'heartbeat';

  /** The local room user identifier carried by the signal. */
  user_id: string;

  /**
   * Creates a room heartbeat signal.
   *
   * @param userId The RTC user identifier.
   */
  constructor(
    userId: string
  ) {
    super();
    this.user_id = userId;
  }
}

/** Encodes generation, interaction, quality, and heartbeat signals with runtime fields. */
export class RoomEvent {

  /**
   * Encodes target dimensions and bitrate into a quality change signal.
   *
   * @param userId The RTC user identifier.
   * @param taskId The current generation task identifier.
   * @param size The requested result stream dimensions, in pixels.
   *
   * @returns The change_target_size JSON for RTC room submission.
   */
  static changeTargetSize(
    userId: string,
    taskId: string,
    size: ImageSize
  ): string {
    return JSON.stringify(new ChangeTargetSizeRoomEvent(
      userId,
      taskId,
      size
    ));
  }

  /**
   * Encodes generation parameters into a task start signal.
   *
   * @param userId The RTC user identifier.
   * @param taskId The current generation task identifier.
   * @param videoFormat The media output or transport format.
   * @param context The prompt, reference image, and face detection configuration.
   * @param faceRestoration Whether to enable face restoration.
   * @param targetSize The optional result stream target dimensions.
   * @param paddingContain Whether to preserve media aspect ratio with server-side padding.
   * @param extraParams The static generation parameters passed internally by the SDK.
   *
   * @returns The JSON containing task, runtime, and generation parameters.
   */
  static start(
    userId: string,
    taskId: string,
    videoFormat: RealtimeVideoFormat,
    context: RealtimeContext,
    faceRestoration: boolean = false,
    targetSize?: ImageSize,
    paddingContain: boolean = false,
    extraParams?: RealtimeGenerationParameters
  ): string {
    return JSON.stringify(new StartRoomEvent(
      userId,
      taskId,
      videoFormat,
      context,
      faceRestoration,
      targetSize,
      paddingContain,
      extraParams
    ));
  }

  /**
   * Encodes updated generation conditions for the current task.
   *
   * @param userId The RTC user identifier.
   * @param taskId The current generation task identifier.
   * @param videoFormat The media output or transport format.
   * @param context The prompt, reference image, and face detection configuration.
   * @param faceRestoration Whether to enable face restoration.
   * @param targetSize The optional result stream target dimensions.
   * @param paddingContain Whether to preserve media aspect ratio with server-side padding.
   * @param extraParams The static generation parameters passed internally by the SDK.
   *
   * @returns The JSON containing runtime and generation conditions.
   */
  static changeCondition(
    userId: string,
    taskId: string,
    videoFormat: RealtimeVideoFormat,
    context: RealtimeContext,
    faceRestoration: boolean = false,
    targetSize?: ImageSize,
    paddingContain: boolean = false,
    extraParams?: RealtimeGenerationParameters
  ): string {
    return JSON.stringify(new ChangeConditionRoomEvent(
      userId,
      taskId,
      videoFormat,
      context,
      faceRestoration,
      targetSize,
      paddingContain,
      extraParams
    ));
  }

  /**
   * Encodes a task identifier into a generation stop signal.
   *
   * @param userId The RTC user identifier.
   * @param taskId The current generation task identifier.
   *
   * @returns The JSON containing user, task, and runtime information.
   */
  static stop(
    userId: string,
    taskId: string
  ): string {
    return JSON.stringify(new StopRoomEvent(
      userId,
      taskId
    ));
  }

  /**
   * Encodes normalized points into the current task's trajectory signal.
   *
   * @param userId The RTC user identifier.
   * @param taskId The current generation task identifier.
   * @param points The touch points to submit or draw.
   *
   * @returns The JSON containing task and touch data.
   */
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

  /**
   * Encodes the local user into a room heartbeat.
   *
   * @param userId The RTC user identifier.
   *
   * @returns The JSON containing runtime and user identity.
   */
  static heartbeat(
    userId: string
  ): string {
    return JSON.stringify(new HeartbeatRoomEvent(userId));
  }
}
