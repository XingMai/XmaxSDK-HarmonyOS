//
//  XmaxRealtimeGenerationManager.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { ImageSize } from '../../service/media/ImageSize';
import { MediaService } from '../../service/media/MediaService';
import { MediaServicing } from '../../service/media/MediaServicing';
import { util } from '@kit.ArkTS';
import { RUNTIME_PLATFORM } from '../../foundation/runtime/RuntimeInfo';
import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import {
  XmaxError,
  XmaxErrorCode
} from '../../foundation/errors/XmaxError';
import { MediaControlling } from '../../media/MediaControlling';
import { RealtimeContext } from '../../service/realtime/RealtimeContext';
import { RealtimeGenerationParameters } from '../../service/realtime/RealtimeGenerationOptions';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import { StreamControlling } from '../../stream/StreamControlling';

/**
 * 验证生成操作是否仍有效；失效时抛出取消错误。
 *
 * @returns 无返回值。
 */
type GenerationValidity = () => void;

/**
 * 等待指定任务的结果流确认，支持操作取消。
 *
 * @param confirmation 等待指定任务生成结果流确认的 Promise。
 * @returns 操作完成时兑现的 Promise。
 */
type GenerationConfirmationWait = (confirmation: Promise<void>) => Promise<void>;

const TASK_ID_PREFIX: string = 'task-';

/** 协调生成信令、远端结果确认、条件更新和交互任务。 */
export class XmaxRealtimeGenerationManager {

  /** 媒体与传输依赖 */
  private readonly mediaController: MediaControlling;
  private readonly streamController: StreamControlling;
  private readonly mediaService: MediaServicing;

  /** 已生效与启动中的生成条件 */
  private currentContext: RealtimeContext | null = null;
  private startingContext: RealtimeContext | null = null;
  /** 静态生成配置仅在 SDK 内缓存，不写入公开的 RealtimeContext。 */
  private currentExtraParams?: RealtimeGenerationParameters;
  private startingExtraParams?: RealtimeGenerationParameters;

  /** 启动中的视频格式 */
  private startingVideoFormat: RealtimeVideoFormat | null = null;

  /** 人脸修复的已生效与待确认配置 */
  private currentFaceRestoration: boolean = false;
  private startingFaceRestoration: boolean | null = null;

  /**
   * 创建生成流程 Manager。
   *
   * @param mediaController 生成期间的统一媒体和交互组件。
   * @param streamController 发送生成信令并匹配远端结果流的统一流组件。
   * @param mediaService 计算媒体处理、生成与目标尺寸的业务服务。
   * @returns 新建的 XmaxRealtimeGenerationManager 实例。
   */
  constructor(
    mediaController: MediaControlling,
    streamController: StreamControlling,
    mediaService: MediaServicing = new MediaService()
  ) {
    // 业务层组件
    this.mediaController = mediaController;
    this.streamController = streamController;
    this.mediaService = mediaService;
  }

  /**
   * 判断已确认的任务是否使用静态图片输入；此类任务可在收到交互后才输出视频。
   *
   * @returns 当前生成条件是否启用静态图片输入。
   */
  get usesStaticInput(): boolean {
    return this.currentExtraParams?.static_generate ?? false;
  }

  /**
   * 在开始生成和修改资源前验证首次生成所需的条件。
   *
   * @param context 生成提示词、参考图和人脸检测配置。
   * @returns 无返回值。
   */
  validateContext(context?: RealtimeContext, extraParams?: RealtimeGenerationParameters): void {
    const resolved: RealtimeGenerationParameters | undefined =
      context === undefined ? this.currentExtraParams : extraParams;
    if (resolved?.static_generate && !resolved.static_image_path) {
      throw new XmaxError(XmaxErrorCode.INVALID_CONFIGURATION,
        'Static generation requires a non-empty static_image_path');
    }
    if (context === undefined && this.currentContext === null) {
      throw new XmaxError(XmaxErrorCode.INVALID_CONFIGURATION,
        'A realtime context is required for the first generation');
    }
  }

  /**
   * 启动生成并等待与任务匹配的远端结果流。
   *
   * @param videoFormat 当前本地输入的视频格式。
   * @param context 可选的生成条件；首次生成时必须提供。
   * @param ensureCurrent 确认当前生成操作仍然有效的回调。
   * @param waitForConfirmation 等待指定生成任务结果流确认的异步函数。
   * @param faceRestoration 原始人脸回贴；内部重启省略时保留当前设置，公开调用显式传入默认 false。
   * @param targetSize 可选的生成结果流目标尺寸。
   * @returns 确认远端结果开始后的生成任务标识。
   */
  async start(
    videoFormat: RealtimeVideoFormat,
    context: RealtimeContext | undefined,
    ensureCurrent: GenerationValidity,
    waitForConfirmation?: GenerationConfirmationWait,
    faceRestoration?: boolean,
    targetSize?: ImageSize,
    extraParams?: RealtimeGenerationParameters
  ): Promise<string> {
    this.validateContext(context, extraParams);
    const resolvedContext: RealtimeContext | null = context ?? this.currentContext;
    if (resolvedContext === null) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'A realtime context is required for the first generation'
      );
    }

    const taskId: string = XmaxRealtimeGenerationManager.createTaskId();
    this.startingContext = resolvedContext;
    this.startingExtraParams = context === undefined ? this.currentExtraParams : extraParams;
    this.startingVideoFormat = videoFormat;
    this.startingFaceRestoration = faceRestoration ?? this.currentFaceRestoration;
    try {
      const confirmation: Promise<void> = this.streamController.beginGeneration(
        taskId, this.generationFormat(videoFormat), resolvedContext, this.startingFaceRestoration,
        targetSize ?? this.targetSize(videoFormat), this.mediaController.usesContainPadding, this.startingExtraParams);
      await (waitForConfirmation === undefined ? confirmation : waitForConfirmation(confirmation));
      ensureCurrent();

      this.mediaController.start(taskId, this.startingVideoFormat ?? videoFormat);
      // 确认等待期可能并入了新条件，与 startingVideoFormat 一样以等待期内的最新值为准。
      this.currentContext = this.startingContext ?? resolvedContext;
      this.currentExtraParams = this.startingExtraParams;
      this.currentFaceRestoration = this.startingFaceRestoration ?? this.currentFaceRestoration;
      return taskId;
    } catch (error) {
      try {
        this.stop(taskId);
      } catch (cleanupError) {
        XmaxLogger.error(`${XmaxLogger.localized("取消生成等待失败 (Failed to Cancel Generation Wait)\n└─ 原因：", "取消生成等待失败 (Failed to Cancel Generation Wait)\n└─ Reason: ")}${XmaxError.from(cleanupError).message}`, 'Realtime');
      }
      throw XmaxError.from(error);
    } finally {
      this.startingContext = null;
      this.startingExtraParams = undefined;
      this.startingVideoFormat = null;
      this.startingFaceRestoration = null;
    }
  }

  /**
   * 同步正在启动的媒体格式，并更新当前任务的交互坐标基准。
   *
   * @param format 当前处理后的本地媒体格式。
   * @returns 无返回值。
   */
  updateVideoFormat(format: RealtimeVideoFormat): void {
    const taskId: string = this.streamController.currentGenerationTaskId;
    const context: RealtimeContext | null = this.startingContext ?? this.currentContext;
    if (taskId.length === 0 || context === null) {
      return;
    }
    this.streamController.updateGeneration(taskId, this.generationFormat(format), context,
      this.startingFaceRestoration ?? this.currentFaceRestoration, undefined, this.mediaController.usesContainPadding,
      this.startingContext !== null ? this.startingExtraParams : this.currentExtraParams);
    if (this.startingContext !== null) {
      this.startingVideoFormat = format;
    } else {
      this.mediaController.start(taskId, format);
    }
  }

  /**
   * 更新活动生成任务的交互绑定和可选生成条件。
   *
   * @param taskId 当前生成任务标识。
   * @param videoFormat 当前本地输入的视频格式。
   * @param context 可选的新生成条件；未传入时复用缓存条件。
   * @param faceRestoration 可选的人脸回贴设置；与 context 均省略时仅恢复交互绑定。
   * @returns 无返回值。
   */
  update(
    taskId: string,
    videoFormat: RealtimeVideoFormat,
    context?: RealtimeContext,
    faceRestoration?: boolean,
    extraParams?: RealtimeGenerationParameters
  ): void {
    this.mediaController.start(taskId, videoFormat);

    if (context === undefined && faceRestoration === undefined) {
      return;
    }
    const resolvedContext: RealtimeContext | null = context ?? this.startingContext ?? this.currentContext;
    if (resolvedContext === null) {
      throw new XmaxError(XmaxErrorCode.INVALID_CONFIGURATION,
        'A realtime context is required for the first generation');
    }
    const resolvedFaceRestoration: boolean =
      faceRestoration ?? this.startingFaceRestoration ?? this.currentFaceRestoration;
    const resolvedExtraParams: RealtimeGenerationParameters | undefined = context !== undefined ? extraParams :
      this.startingContext !== null ? this.startingExtraParams : this.currentExtraParams;

    this.streamController.updateGeneration(
      taskId,
      this.generationFormat(videoFormat),
      resolvedContext,
      resolvedFaceRestoration,
      undefined,
      this.mediaController.usesContainPadding,
      resolvedExtraParams
    );
    // 等待确认中的启动以 startingContext 为准，确认时统一落地，避免覆盖新条件。
    if (this.startingContext !== null) {
      this.startingContext = resolvedContext;
      this.startingExtraParams = resolvedExtraParams;
      this.startingFaceRestoration = resolvedFaceRestoration;
    } else {
      this.currentContext = resolvedContext;
      this.currentExtraParams = resolvedExtraParams;
      this.currentFaceRestoration = resolvedFaceRestoration;
    }
  }

  /**
   * 根据模型规则计算生成画布格式，保留帧率和编码选项。
   *
   * @param format 当前处理后的本地媒体格式。
   * @returns 满足生成画布尺寸约束的视频格式。
   */
  private generationFormat(format: RealtimeVideoFormat): RealtimeVideoFormat {
    const size: ImageSize = this.mediaService.resolveGenerationSize(new ImageSize(format.width, format.height));
    return size.width === format.width && size.height === format.height ? format :
      format.resized(size.width, size.height);
  }

  /**
   * 计算适合当前媒体比例与模型约束的结果流目标尺寸。
   *
   * @param format 当前处理后的本地媒体格式。
   * @returns 结果流请求使用的目标尺寸。
   */
  private targetSize(format: RealtimeVideoFormat): ImageSize {
    const size: ImageSize = new ImageSize(format.width, format.height);
    // 内部独立使用时的回退值；实时 Manager 会显式传入调档后的回传尺寸。
    return this.mediaService.resolveTargetSize(size, size);
  }

  /**
   * 停止指定生成任务及其交互和远端流等待。
   *
   * @param taskId 需要停止的生成任务标识。
   * @returns 无返回值。
   */
  stop(taskId: string): void {
    if (taskId.length > 0 && this.streamController.currentGenerationTaskId !== taskId) {
      return;
    }
    this.mediaController.stop();

    this.streamController.stopGeneration(taskId);
  }

  /**
   * 清除缓存的生成条件并停止当前生成任务。
   *
   * @param taskId 可选的生成任务标识；未传入时停止当前等待任务。
   * @returns 无返回值。
   */
  reset(taskId: string = ''): void {
    this.currentContext = null;
    this.currentExtraParams = undefined;
    this.currentFaceRestoration = false;
    this.stop(taskId);
  }

  /**
   * 创建用于关联生成信令和结果流的任务标识。
   *
   * @returns 本次生成使用的唯一任务标识。
   */
  private static createTaskId(): string {
    const uuid: string = util.generateRandomUUID(true).replace(/-/g, '');
    const bytes: Uint8Array = new Uint8Array(16);
    for (let index: number = 0; index < bytes.length; index++) {
      bytes[index] = Number.parseInt(uuid.substring(index * 2, index * 2 + 2), 16);
    }

    const encoded: string = new util.Base64Helper().encodeToStringSync(bytes)
      .replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
    return `${TASK_ID_PREFIX}${encoded}?os=${RUNTIME_PLATFORM}`;
  }

}
