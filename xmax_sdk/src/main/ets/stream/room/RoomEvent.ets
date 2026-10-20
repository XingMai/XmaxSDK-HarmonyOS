//
//  RoomEvent.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
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

/** 为业务房间信令提供统一的运行环境字段。 */
class RuntimeRoomEvent {

  /** 信令运行环境信息 */
  readonly runtime: RuntimeInfoPayload = RuntimeInfo.current.toPayload();
}

/** 序列化生成画布、生成条件、结果流尺寸和码率预算。 */
class GenerationParameters {

  /** 生成画布与条件 */
  model: string = GENERATION_MODEL;
  size: number[];
  prompt: string;
  ref_image_path?: string;
  /** 是否启用静态图片生成及其服务端输入地址。 */
  static_generate?: boolean;
  static_image_path?: string;
  detection: boolean;
  face_replace: boolean;

  /** 结果流目标尺寸与码率 */
  target_size?: number[];
  min_bitrate?: number;
  max_bitrate?: number;

  /** 媒体比例与补边策略 */
  padding?: string;

  /**
   * 创建生成信令参数。
   *
   * @param videoFormat 媒体输出或传输所需的视频规格。
   * @param context 生成提示词、参考图和人脸检测配置。
   * @param faceRestoration 是否启用人脸修复。
   * @param targetSize 可选的生成结果流目标尺寸。
   * @param paddingContain 是否保持媒体比例并由服务端补边显示。
   * @param extraParams SDK 内部传递的静态生成配置。
   * @returns 新建的 GenerationParameters 实例。
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

/** 序列化结果流目标尺寸及其码率范围，供服务端调节下行输出。 */
class TargetSizeParameters {

  /** 结果流目标尺寸 */
  readonly target_size: number[];

  /** 结果流码率边界 */
  readonly min_bitrate: number = 100;
  readonly max_bitrate: number;

  /**
   * 创建结果流尺寸与码率参数。
   *
   * @param size 需要计算或发送的画面尺寸。
   * @returns 新建的 TargetSizeParameters 实例。
   */
  constructor(size: ImageSize) {
    const budget: VideoBitrateBudget = EncodingBitratePolicy.resolve(new RealtimeVideoFormat(size.width, size.height, 24));
    this.target_size = [size.width, size.height];
    this.max_bitrate = Math.min(10000, budget.maximum);
  }
}

/** 请求调整指定生成任务的结果流目标尺寸和码率。 */
class ChangeTargetSizeRoomEvent extends RuntimeRoomEvent {

  /** 事件路由与任务身份 */
  readonly event: string = 'change_target_size';
  readonly user_id: string;
  readonly uid: string;

  /** 结果流目标配置 */
  readonly params: TargetSizeParameters;

  /**
   * 创建结果流调档信令。
   *
   * @param userId RTC 用户标识。
   * @param taskId 当前生成任务标识。
   * @param size 需要计算或发送的画面尺寸。
   * @returns 新建的 ChangeTargetSizeRoomEvent 实例。
   */
  constructor(userId: string, taskId: string, size: ImageSize) {
    super();
    this.user_id = userId;
    this.uid = taskId;
    this.params = new TargetSizeParameters(size);
  }
}

/** 携带任务标识和生成参数的启动信令。 */
class StartRoomEvent extends RuntimeRoomEvent {

  /** 事件类型 */
  event: string = 'start';

  /** 生成配置 */
  params: GenerationParameters;

  /** 用户与任务身份 */
  user_id: string;
  uid: string;

  /**
   * 创建生成启动信令。
   *
   * @param userId RTC 用户标识。
   * @param taskId 当前生成任务标识。
   * @param videoFormat 媒体输出或传输所需的视频规格。
   * @param context 生成提示词、参考图和人脸检测配置。
   * @param faceRestoration 是否启用人脸修复。
   * @param targetSize 可选的生成结果流目标尺寸。
   * @param paddingContain 是否保持媒体比例并由服务端补边显示。
   * @param extraParams SDK 内部传递的静态生成配置。
   * @returns 新建的 StartRoomEvent 实例。
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
    this.params = new GenerationParameters(videoFormat, context, faceRestoration, targetSize, paddingContain, extraParams);
    this.user_id = userId;
    this.uid = taskId;
  }
}

/** 携带任务标识和新生成条件的更新信令。 */
class ChangeConditionRoomEvent extends RuntimeRoomEvent {

  /** 事件类型 */
  event: string = 'change_condition';

  /** 生成条件 */
  params: GenerationParameters;

  /** 用户与任务身份 */
  user_id: string;
  uid: string;

  /**
   * 创建生成条件更新信令。
   *
   * @param userId RTC 用户标识。
   * @param taskId 当前生成任务标识。
   * @param videoFormat 媒体输出或传输所需的视频规格。
   * @param context 生成提示词、参考图和人脸检测配置。
   * @param faceRestoration 是否启用人脸修复。
   * @param targetSize 可选的生成结果流目标尺寸。
   * @param paddingContain 是否保持媒体比例并由服务端补边显示。
   * @param extraParams SDK 内部传递的静态生成配置。
   * @returns 新建的 ChangeConditionRoomEvent 实例。
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
    this.params = new GenerationParameters(videoFormat, context, faceRestoration, targetSize, paddingContain, extraParams);
    this.user_id = userId;
    this.uid = taskId;
  }
}

/** 请求停止指定生成任务的信令。 */
class StopRoomEvent extends RuntimeRoomEvent {

  /** 事件类型与任务身份 */
  event: string = 'stop';
  user_id: string;
  uid: string;

  /**
   * 创建生成停止信令。
   *
   * @param userId RTC 用户标识。
   * @param taskId 当前生成任务标识。
   * @returns 新建的 StopRoomEvent 实例。
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

/** 携带指定任务归一化交互点的轨迹信令。 */
class TracksRoomEvent extends RuntimeRoomEvent {

  /** 事件类型 */
  event: string = 'tracks';

  /** 交互触点数据 */
  tracks: number[][];

  /** 用户与任务身份 */
  user_id: string;
  uid: string;

  /**
   * 创建交互轨迹信令。
   *
   * @param userId RTC 用户标识。
   * @param taskId 当前生成任务标识。
   * @param points 本次提交或绘制的触点集合。
   * @returns 新建的 TracksRoomEvent 实例。
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

/** 保持 RTC 房间业务活跃的心跳信令。 */
class HeartbeatRoomEvent extends RuntimeRoomEvent {

  /** 心跳事件与用户身份 */
  event: string = 'heartbeat';
  user_id: string;

  /**
   * 创建房间心跳信令。
   *
   * @param userId RTC 用户标识。
   * @returns 新建的 HeartbeatRoomEvent 实例。
   */
  constructor(userId: string) {
    super();
    this.user_id = userId;
  }
}

/** 将生成、交互、调档和心跳操作编码为带运行环境信息的房间信令。 */
export class RoomEvent {
  /**
   * 将结果流目标尺寸与码率预算编码为调档信令。
   *
   * @param userId RTC 用户标识。
   * @param taskId 当前生成任务标识。
   * @param size 需要计算或发送的画面尺寸。
   * @returns 可提交到 RTC 房间的 change_target_size JSON 文本。
   */
  static changeTargetSize(userId: string, taskId: string, size: ImageSize): string {
    return JSON.stringify(new ChangeTargetSizeRoomEvent(userId, taskId, size));
  }

  /**
   * 将生成参数编码为任务启动信令。
   *
   * @param userId RTC 用户标识。
   * @param taskId 当前生成任务标识。
   * @param videoFormat 媒体输出或传输所需的视频规格。
   * @param context 生成提示词、参考图和人脸检测配置。
   * @param faceRestoration 是否启用人脸修复。
   * @param targetSize 可选的生成结果流目标尺寸。
   * @param paddingContain 是否保持媒体比例并由服务端补边显示。
   * @param extraParams SDK 内部传递的静态生成配置。
   * @returns 包含任务、运行环境和生成参数的 JSON 文本。
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
    return JSON.stringify(new StartRoomEvent(userId, taskId, videoFormat, context, faceRestoration, targetSize, paddingContain, extraParams));
  }

  /**
   * 将新的生成条件编码为更新信令，供当前任务使用。
   *
   * @param userId RTC 用户标识。
   * @param taskId 当前生成任务标识。
   * @param videoFormat 媒体输出或传输所需的视频规格。
   * @param context 生成提示词、参考图和人脸检测配置。
   * @param faceRestoration 是否启用人脸修复。
   * @param targetSize 可选的生成结果流目标尺寸。
   * @param paddingContain 是否保持媒体比例并由服务端补边显示。
   * @param extraParams SDK 内部传递的静态生成配置。
   * @returns 包含运行环境和生成条件的 JSON 文本。
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
   * 将任务标识编码为停止生成信令。
   *
   * @param userId RTC 用户标识。
   * @param taskId 当前生成任务标识。
   * @returns 包含用户、任务与运行环境的 JSON 文本。
   */
  static stop(
    userId: string,
    taskId: string
  ): string {
    return JSON.stringify(new StopRoomEvent(userId, taskId));
  }

  /**
   * 将归一化交互点编码为当前任务的轨迹信令。
   *
   * @param userId RTC 用户标识。
   * @param taskId 当前生成任务标识。
   * @param points 本次提交或绘制的触点集合。
   * @returns 包含任务与触点数据的 JSON 文本。
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
   * 将本地用户标识编码为房间心跳信令。
   *
   * @param userId RTC 用户标识。
   * @returns 包含运行环境与用户标识的 JSON 文本。
   */
  static heartbeat(userId: string): string {
    return JSON.stringify(new HeartbeatRoomEvent(userId));
  }
}
