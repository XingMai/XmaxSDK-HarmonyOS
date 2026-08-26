import { common } from '@kit.AbilityKit';
import {
  EngineConfig,
  RTCEngine
} from '@bytertc/volcenginertc';
import {
  XmaxError,
  XmaxErrorCode
} from '../errors/XmaxError';

const RTC_APP_ID: string = '69a177e226e9b90176a86b96';

/** 表示对全局 RTC Engine 的独占使用权。 */
export class RtcEngineLease {

  readonly engine: RTCEngine;

  /**
   * 创建 RTC Engine 租约。
   *
   * @param engine 当前租约持有的 RTC Engine。
   */
  constructor(engine: RTCEngine) {
    this.engine = engine;
  }
}

/** 保存等待 RTC Engine 可用的请求。 */
class RtcEngineRequest {

  readonly resolve: () => void;

  /**
   * 创建 RTC Engine 等待请求。
   *
   * @param resolve Engine 可用时调用的完成方法。
   */
  constructor(resolve: () => void) {
    this.resolve = resolve;
  }
}

/** 管理全局 RTC Engine 的独占创建、租用和销毁。 */
export class RtcEngineManager {

  // RTC 资源
  private static activeLease: RtcEngineLease | null = null;
  private static readonly requests: RtcEngineRequest[] = [];
  private static initializationPromise: Promise<RTCEngine> | null = null;
  private static destructionPromise: Promise<void> | null = null;

  /**
   * 等待并获取一份独占 RTC Engine 租约。
   *
   * @param context 创建 RTC Engine 使用的平台上下文。
   * @returns RTC Engine 创建完成后的独占租约。
   */
  static async acquire(
    context: common.UIAbilityContext
  ): Promise<RtcEngineLease> {
    while (RtcEngineManager.activeLease !== null ||
      RtcEngineManager.initializationPromise !== null ||
      RtcEngineManager.destructionPromise !== null) {
      await RtcEngineManager.waitForAvailability();
    }

    const initializationPromise: Promise<RTCEngine> =
      RtcEngineManager.create(context);
    RtcEngineManager.initializationPromise = initializationPromise;

    try {
      const engine: RTCEngine = await initializationPromise;
      const lease = new RtcEngineLease(engine);
      RtcEngineManager.activeLease = lease;

      return lease;
    } catch (error) {
      throw XmaxError.from(error);
    } finally {
      if (RtcEngineManager.initializationPromise === initializationPromise) {
        RtcEngineManager.initializationPromise = null;
      }
      if (RtcEngineManager.activeLease === null) {
        RtcEngineManager.notifyNextRequest();
      }
    }
  }

  /**
   * 释放当前有效租约并销毁对应 RTC Engine。
   *
   * @param lease 待释放的 RTC Engine 租约。
   * @returns Engine 销毁完成后的 Promise。
   */
  static async release(lease: RtcEngineLease): Promise<void> {
    if (RtcEngineManager.activeLease !== lease) {
      return;
    }

    RtcEngineManager.activeLease = null;
    const destructionPromise: Promise<void> =
      RtcEngineManager.destroy(lease.engine);
    RtcEngineManager.destructionPromise = destructionPromise;

    try {
      await destructionPromise;
    } finally {
      if (RtcEngineManager.destructionPromise === destructionPromise) {
        RtcEngineManager.destructionPromise = null;
      }
      RtcEngineManager.notifyNextRequest();
    }
  }

  /**
   * 将当前请求加入 RTC Engine 可用等待队列。
   *
   * @returns 收到下一次可用通知后的 Promise。
   */
  private static waitForAvailability(): Promise<void> {
    return new Promise<void>((resolve): void => {
      RtcEngineManager.requests.push(new RtcEngineRequest(resolve));
    });
  }

  /**
   * 唤醒等待队列中的下一个 RTC Engine 请求。
   *
   * @returns 无返回值。
   */
  private static notifyNextRequest(): void {
    const request: RtcEngineRequest | undefined =
      RtcEngineManager.requests.shift();
    if (request !== undefined) {
      request.resolve();
    }
  }

  /**
   * 创建并初始化 RTC Engine。
   *
   * @param context 创建 RTC Engine 使用的平台上下文。
   * @returns 初始化完成的 RTC Engine。
   */
  private static async create(
    context: common.UIAbilityContext
  ): Promise<RTCEngine> {
    const engine = new RTCEngine(context);
    const configuration: EngineConfig = {
      app_id: RTC_APP_ID,
      parameters: '{}'
    };
    const result: number = await engine.createRTCEngine(configuration);
    if (result < 0) {
      throw new XmaxError(
        XmaxErrorCode.RTC_ERROR,
        `createRTCEngine failed: ${result}`
      );
    }

    return engine;
  }

  /**
   * 销毁指定 RTC Engine。
   *
   * @param engine 待销毁的 RTC Engine。
   * @returns Engine 销毁完成后的 Promise。
   */
  private static async destroy(engine: RTCEngine): Promise<void> {
    const result: number = await engine.destroyRTCEngine();
    if (result < 0) {
      throw new XmaxError(
        XmaxErrorCode.RTC_ERROR,
        `destroyRTCEngine failed: ${result}`
      );
    }
  }
}
