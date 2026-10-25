//
//  XmaxRealtimeGenerationManager.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
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

/** Verifies generation operation validity, throwing cancellation if invalidated. */
type GenerationValidity = () => void;

/**
 * Waits for a task's result confirmation with cancellation support.
 *
 * @param confirmation The Promise confirming the specified generation task's result stream.
 */
type GenerationConfirmationWait = (
  confirmation: Promise<void>
) => Promise<void>;

const TASK_ID_PREFIX: string = 'task-';

/** Coordinates generation signaling, result confirmation, condition updates, and interactions. */
export class XmaxRealtimeGenerationManager {

  // Media and stream dependencies

  /** The controller owning local media and its RTC engine lifecycle. */
  private readonly mediaController: MediaControlling;

  /** The controller coordinating RTC rooms, streams, and signaling. */
  private readonly streamController: StreamControlling;

  /** The service resolving model-specific media dimensions. */
  private readonly mediaService: MediaServicing;

  // Committed and pending generation conditions

  /** The conditions cached from the active generation task. */
  private currentContext: RealtimeContext | null = null;

  /** The latest conditions pending generation confirmation. */
  private startingContext: RealtimeContext | null = null;

  /** Static generation configuration is cached internally, outside the public RealtimeContext. */
  private currentExtraParams?: RealtimeGenerationParameters;

  /** The static-image parameters pending generation confirmation. */
  private startingExtraParams?: RealtimeGenerationParameters;

  // Pending video format

  /** The media format awaiting generation confirmation. */
  private startingVideoFormat: RealtimeVideoFormat | null = null;

  // Committed and pending face restoration settings

  /** The face restoration setting of the active task. */
  private currentFaceRestoration: boolean = false;

  /** The face restoration setting pending generation confirmation. */
  private startingFaceRestoration: boolean | null = null;

  /** Creates a generation manager. */
  constructor(
    mediaController: MediaControlling,
    streamController: StreamControlling,
    mediaService: MediaServicing = new MediaService()
  ) {
    // Business components
    this.mediaController = mediaController;
    this.streamController = streamController;
    this.mediaService = mediaService;
  }

  /** Whether the confirmed task uses a static image and may await interaction before output. */
  get usesStaticInput(): boolean {
    return this.currentExtraParams?.static_generate ?? false;
  }

  /**
   * Validates initial generation conditions before starting or changing resources.
   *
   * @param context The prompt, reference image, and face detection configuration.
   */
  validateContext(
    context?: RealtimeContext,
    extraParams?: RealtimeGenerationParameters
  ): void {
    const resolved: RealtimeGenerationParameters | undefined =
      context === undefined ? this.currentExtraParams : extraParams;
    if (resolved?.static_generate && !resolved.static_image_path) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Static generation requires a non-empty static_image_path'
      );
    }

    if (context === undefined && this.currentContext === null) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'A realtime context is required for the first generation'
      );
    }
  }

  /**
   * Starts generation and waits for the task's matching result stream.
   *
   * @param videoFormat The current local media format.
   * @param context The generation conditions, required for the first request.
   * @param ensureCurrent The callback verifying generation operation validity.
   * @param waitForConfirmation The cancellable result confirmation waiter.
   * @param faceRestoration Whether to restore the original face; internal restarts may retain it,
   * while public calls default to false.
   * @param targetSize The optional result stream target dimensions.
   *
   * @returns The confirmed generation task identifier.
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
    this.validateContext(
      context,
      extraParams
    );

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
        taskId,
        this.generationFormat(videoFormat),
        resolvedContext,
        this.startingFaceRestoration,
        targetSize ?? this.targetSize(videoFormat),
        this.mediaController.usesContainPadding,
        this.startingExtraParams
      );
      await (waitForConfirmation === undefined ? confirmation : waitForConfirmation(confirmation));
      ensureCurrent();

      this.mediaController.start(
        taskId,
        this.startingVideoFormat ?? videoFormat
      );

      // Use the latest conditions and video format merged during confirmation.
      this.currentContext = this.startingContext ?? resolvedContext;
      this.currentExtraParams = this.startingExtraParams;
      this.currentFaceRestoration = this.startingFaceRestoration ?? this.currentFaceRestoration;
      return taskId;
    } catch (error) {
      try {
        this.stop(taskId);
      } catch (cleanupError) {
        XmaxLogger.error(
          `${XmaxLogger.localized("取消生成等待失败 (Failed to Cancel Generation Wait)\n└─ 原因：", "取消生成等待失败 (Failed to Cancel Generation Wait)\n└─ Reason: ")}${XmaxError.from(cleanupError).message}`,
          'Realtime'
        );
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
   * Synchronizes a pending media format and updates the interaction coordinate baseline.
   *
   * @param format The current processed local media format.
   */
  updateVideoFormat(
    format: RealtimeVideoFormat
  ): void {
    const taskId: string = this.streamController.currentGenerationTaskId;
    const context: RealtimeContext | null = this.startingContext ?? this.currentContext;
    if (taskId.length === 0 || context === null) {
      return;
    }

    this.streamController.updateGeneration(
      taskId,
      this.generationFormat(format),
      context,
      this.startingFaceRestoration ?? this.currentFaceRestoration,
      undefined,
      this.mediaController.usesContainPadding,
      this.startingContext !== null ? this.startingExtraParams : this.currentExtraParams
    );

    if (this.startingContext !== null) {
      this.startingVideoFormat = format;
    } else {
      this.mediaController.start(
        taskId,
        format
      );
    }
  }

  /**
   * Updates active interaction bindings and optional generation conditions.
   *
   * @param taskId The current generation task identifier.
   * @param videoFormat The current local media format.
   * @param context The new conditions, or undefined to reuse cached conditions.
   * @param faceRestoration The optional face restoration setting; omitting it and context only
   * restores interaction bindings.
   */
  update(
    taskId: string,
    videoFormat: RealtimeVideoFormat,
    context?: RealtimeContext,
    faceRestoration?: boolean,
    extraParams?: RealtimeGenerationParameters
  ): void {
    this.mediaController.start(
      taskId,
      videoFormat
    );

    if (context === undefined && faceRestoration === undefined) {
      return;
    }

    const resolvedContext: RealtimeContext | null = context ?? this.startingContext ?? this.currentContext;
    if (resolvedContext === null) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'A realtime context is required for the first generation'
      );
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

    // Commit startingContext after confirmation so newer conditions are not overwritten.
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
   * Resolves canvas format from model rules while preserving frame rate and encoder settings.
   *
   * @param format The current processed local media format.
   *
   * @returns The video format satisfying canvas constraints.
   */
  private generationFormat(
    format: RealtimeVideoFormat
  ): RealtimeVideoFormat {
    const size: ImageSize = this.mediaService.resolveGenerationSize(new ImageSize(
      format.width,
      format.height
    ));
    return size.width === format.width && size.height === format.height ? format :
      format.resized(
        size.width,
        size.height
      );
  }

  /**
   * Resolves result dimensions for media aspect ratio and model constraints.
   *
   * @param format The current processed local media format.
   *
   * @returns The requested result stream dimensions.
   */
  private targetSize(
    format: RealtimeVideoFormat
  ): ImageSize {
    const size: ImageSize = new ImageSize(
      format.width,
      format.height
    );
    // A fallback for independent internal use; the realtime manager passes quality-adjusted dimensions explicitly.
    return this.mediaService.resolveTargetSize(
      size,
      size
    );
  }

  /**
   * Stops a task, its interactions, and result-stream wait.
   *
   * @param taskId The generation task to stop.
   */
  stop(
    taskId: string
  ): void {
    if (taskId.length > 0 && this.streamController.currentGenerationTaskId !== taskId) {
      return;
    }

    this.mediaController.stop();

    this.streamController.stopGeneration(taskId);
  }

  /**
   * Clears cached conditions and stops the current generation task.
   *
   * @param taskId The optional task identifier; omission stops the current pending task.
   */
  reset(
    taskId: string = ''
  ): void {
    this.currentContext = null;
    this.currentExtraParams = undefined;
    this.currentFaceRestoration = false;

    this.stop(taskId);
  }

  /**
   * Creates a task identifier linking generation signals and results.
   *
   * @returns The unique generation task identifier.
   */
  private static createTaskId(): string {
    const uuid: string = util.generateRandomUUID(true).replace(
      /-/g,
      ''
    );

    const bytes: Uint8Array = new Uint8Array(16);
    for (let index: number = 0; index < bytes.length; index++) {
      bytes[index] = Number.parseInt(
        uuid.substring(
          index * 2,
          index * 2 + 2
        ),
        16
      );
    }

    const encoded: string = new util.Base64Helper().encodeToStringSync(bytes)
      .replace(
        /\+/g,
        '-'
      ).replace(
        /\//g,
        '_'
      ).replace(
        /=/g,
        ''
      );
    return `${TASK_ID_PREFIX}${encoded}?os=${RUNTIME_PLATFORM}`;
  }

}
