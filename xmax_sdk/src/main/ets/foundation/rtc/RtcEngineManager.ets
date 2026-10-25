//
//  RtcEngineManager.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

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

/** An exclusive lease of the global RTC engine. */
export class RtcEngineLease {

  /** The RTC engine owned by the active lease. */
  readonly engine: RTCEngine;

  /** Creates an RTC engine lease. */
  constructor(
    engine: RTCEngine
  ) {
    this.engine = engine;
  }
}

/** A request waiting for RTC engine availability. */
class RtcEngineRequest {

  /** Completes an asynchronous resource or media result wait. */
  readonly resolve: () => void;

  /** Creates an RTC engine request. */
  constructor(
    resolve: () => void
  ) {
    this.resolve = resolve;
  }
}

/** Manages exclusive RTC engine creation, leasing, and destruction. */
export class RtcEngineManager {

  /** The exclusive RTC engine lease currently in use. */
  private static activeLease: RtcEngineLease | null = null;

  /** The engine requests waiting in admission order. */
  private static readonly requests: RtcEngineRequest[] = [];

  /** The shared in-flight RTC engine initialization. */
  private static initializationPromise: Promise<RTCEngine> | null = null;

  /** The pending engine destruction that must finish before another lease. */
  private static destructionPromise: Promise<void> | null = null;

  /**
   * Waits for and acquires an exclusive RTC engine lease.
   *
   * @param context The platform context for creating the RTC engine.
   *
   * @returns The exclusive lease after engine initialization.
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
   * Releases the valid lease and destroys its RTC engine.
   *
   * The Promise fulfills after engine destruction.
   *
   * @param lease The RTC engine lease to release.
   */
  static async release(
    lease: RtcEngineLease
  ): Promise<void> {
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
   * Queues a request for RTC engine availability.
   *
   * The Promise fulfills by the next availability notification.
   */
  private static waitForAvailability(): Promise<void> {
    return new Promise<void>((resolve): void => {
      RtcEngineManager.requests.push(new RtcEngineRequest(resolve));
    });
  }

  /** Wakes the next pending RTC engine request. */
  private static notifyNextRequest(): void {
    const request: RtcEngineRequest | undefined =
      RtcEngineManager.requests.shift();
    if (request !== undefined) {
      request.resolve();
    }
  }

  /**
   * Creates and initializes an RTC engine.
   *
   * @param context The platform context for creating the RTC engine.
   *
   * @returns The initialized RTC engine.
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
   * Destroys an RTC engine.
   *
   * The Promise fulfills after engine destruction.
   *
   * @param engine The RTC engine to destroy.
   */
  private static async destroy(
    engine: RTCEngine
  ): Promise<void> {
    // Vendor calls may throw instead of returning codes; normalize either failure as XmaxError.
    let result: number;
    try {
      result = await engine.destroyRTCEngine();
    } catch (error) {
      throw new XmaxError(
        XmaxErrorCode.RTC_ERROR,
        `destroyRTCEngine threw: ${XmaxError.from(error).message}`
      );
    }
    if (result < 0) {
      throw new XmaxError(
        XmaxErrorCode.RTC_ERROR,
        `destroyRTCEngine failed: ${result}`
      );
    }
  }
}
