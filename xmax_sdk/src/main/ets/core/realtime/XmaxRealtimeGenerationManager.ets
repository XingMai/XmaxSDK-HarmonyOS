import { util } from '@kit.ArkTS';
import { RUNTIME_PLATFORM } from '../../foundation/runtime/RuntimeInfo';
import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import {
  XmaxError,
  XmaxErrorCode
} from '../../foundation/errors/XmaxError';
import { MediaControlling } from '../../media/MediaControlling';
import { RealtimeContext } from '../../service/realtime/RealtimeContext';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import { StreamControlling } from '../../stream/StreamControlling';

type GenerationValidity = () => void;
type GenerationConfirmationWait = (confirmation: Promise<void>) => Promise<void>;

const TASK_ID_PREFIX: string = 'task-';

/** 协调生成信令、远端结果确认、条件更新和交互任务。 */
export class XmaxRealtimeGenerationManager {

  // 业务层组件
  private readonly mediaController: MediaControlling;
  private readonly streamController: StreamControlling;

  // 生成资源
  private currentContext: RealtimeContext | null = null;

  /**
   * 创建生成流程 Manager。
   *
   * @param mediaController 生成期间的统一媒体和交互组件。
   * @param streamController 发送生成信令并匹配远端结果流的统一流组件。
   */
  constructor(
    mediaController: MediaControlling,
    streamController: StreamControlling
  ) {
    // 业务层组件
    this.mediaController = mediaController;
    this.streamController = streamController;
  }

  /**
   * 启动生成并等待与任务匹配的远端结果流。
   *
   * @param videoFormat 当前本地输入的视频格式。
   * @param context 可选的生成条件；首次生成时必须提供。
   * @param ensureCurrent 确认当前生成操作仍然有效的回调。
   * @returns 确认远端结果开始后的生成任务标识。
   */
  async start(
    videoFormat: RealtimeVideoFormat,
    context: RealtimeContext | undefined,
    ensureCurrent: GenerationValidity,
    waitForConfirmation?: GenerationConfirmationWait
  ): Promise<string> {
    const resolvedContext: RealtimeContext | null = context ?? this.currentContext;
    if (resolvedContext === null) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'A realtime context is required for the first generation'
      );
    }

    const taskId: string = XmaxRealtimeGenerationManager.createTaskId();
    const confirmation: Promise<void> = this.streamController.beginGeneration(
      taskId,
      videoFormat,
      resolvedContext
    );
    try {
      await (waitForConfirmation === undefined ? confirmation : waitForConfirmation(confirmation));
      ensureCurrent();

      this.mediaController.start(taskId, videoFormat);
      this.currentContext = resolvedContext;
      return taskId;
    } catch (error) {
      try {
        this.stop(taskId);
      } catch (cleanupError) {
        XmaxLogger.error(`取消生成等待失败\n└─ 原因：${XmaxError.from(cleanupError).message}`, 'Realtime');
      }
      throw XmaxError.from(error);
    }
  }

  /**
   * 更新活动生成任务的交互绑定和可选生成条件。
   *
   * @param taskId 当前生成任务标识。
   * @param videoFormat 当前本地输入的视频格式。
   * @param context 可选的新生成条件；未传入时仅恢复交互绑定。
   * @returns 无返回值。
   */
  update(
    taskId: string,
    videoFormat: RealtimeVideoFormat,
    context?: RealtimeContext
  ): void {
    this.mediaController.start(taskId, videoFormat);

    if (context === undefined) {
      return;
    }

    this.streamController.updateGeneration(
      taskId,
      videoFormat,
      context
    );
    this.currentContext = context;
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
    this.stop(taskId);
  }

  /** @returns task- 前缀加完整 UUID 字节的无填充 Base64URL，并以 os 查询参数标识平台。 */
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
