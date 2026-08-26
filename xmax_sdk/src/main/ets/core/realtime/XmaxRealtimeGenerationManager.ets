import { util } from '@kit.ArkTS';
import {
  XmaxError,
  XmaxErrorCode
} from '../../foundation/errors/XmaxError';
import { MediaControlling } from '../../media/MediaControlling';
import { RealtimeContext } from '../../service/realtime/RealtimeContext';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import { TransportControlling } from '../../transport/TransportControlling';

type GenerationValidity = () => void;
type GenerationStartedHandler = () => Promise<void>;

const TASK_ID_PREFIX: string = 'task-';
const TASK_ID_ALPHABET: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

/** 协调生成信令、远端结果确认、条件更新和交互任务。 */
export class XmaxRealtimeGenerationManager {

  // 业务层组件
  private readonly mediaController: MediaControlling;
  private readonly transportController: TransportControlling;

  // 生成资源
  private currentContext: RealtimeContext | null = null;

  // 运行状态
  private conditionVersion: number = 0;

  /**
   * 创建生成流程 Manager。
   *
   * @param mediaController 生成期间的统一媒体和交互组件。
   * @param transportController 发送生成信令并匹配远端结果流的统一传输组件。
   */
  constructor(
    mediaController: MediaControlling,
    transportController: TransportControlling
  ) {
    // 业务层组件
    this.mediaController = mediaController;
    this.transportController = transportController;
  }

  /**
   * 启动生成并等待与任务匹配的远端结果流。
   *
   * @param videoFormat 当前本地输入的视频格式。
   * @param context 可选的生成条件；首次生成时必须提供。
   * @param ensureCurrent 确认当前生成操作仍然有效的回调。
   * @param onGenerationStarted 生成信令发出后需要执行的本地媒体操作。
   * @returns 确认远端结果开始后的生成任务标识。
   */
  async start(
    videoFormat: RealtimeVideoFormat,
    context: RealtimeContext | undefined,
    ensureCurrent: GenerationValidity,
    onGenerationStarted: GenerationStartedHandler
  ): Promise<string> {
    const resolvedContext: RealtimeContext | null = context ?? this.currentContext;
    if (resolvedContext === null) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'A realtime context is required for the first generation'
      );
    }

    const taskId: string = XmaxRealtimeGenerationManager.createTaskId();
    const confirmation: Promise<void> = this.transportController.beginGeneration(
      taskId,
      videoFormat,
      resolvedContext
    );
    this.conditionVersion = 0;

    try {
      await onGenerationStarted();
      await confirmation;
      ensureCurrent();

      this.mediaController.start(taskId, videoFormat);
      this.currentContext = resolvedContext;
      return taskId;
    } catch (error) {
      this.stop(taskId);
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

    this.conditionVersion++;
    this.transportController.updateGeneration(
      taskId,
      this.conditionVersion,
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
    this.mediaController.stop();

    this.transportController.stopGeneration(taskId);
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

  /** @returns 带 `task-` 前缀的紧凑随机生成任务标识。 */
  private static createTaskId(): string {
    const uuid: string = util.generateRandomUUID(true).replace(/-/g, '');
    const randomHex: string = uuid.substring(0, 12) +
      uuid.substring(13, 16) +
      uuid.substring(17, 26);
    let encoded: string = '';

    for (let index: number = 0; index < randomHex.length; index += 3) {
      const value: number = Number.parseInt(randomHex.substring(index, index + 3), 16);
      encoded += TASK_ID_ALPHABET.charAt(value >> 6);
      encoded += TASK_ID_ALPHABET.charAt(value & 63);
    }

    return TASK_ID_PREFIX + encoded;
  }

}
