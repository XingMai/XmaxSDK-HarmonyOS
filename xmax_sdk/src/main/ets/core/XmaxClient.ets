import { common } from '@kit.AbilityKit';
import {
  XmaxError,
  XmaxErrorCode
} from '../foundation/errors/XmaxError';
import { MediaService } from '../service/media/MediaService';
import { MediaServicing } from '../service/media/MediaServicing';
import { ApiService } from '../service/network/ApiService';
import { ApiServicing } from '../service/network/ApiServicing';
import { XmaxConfiguration } from './XmaxConfiguration';
import { RealtimeConfiguration } from './realtime/RealtimeConfiguration';
import { XmaxRealtimeManaging } from './realtime/XmaxRealtimeManaging';
import { XmaxRealtimeManager } from './realtime/XmaxRealtimeManager';
import { XmaxStorageManaging } from './storage/XmaxStorageManaging';
import { XmaxStorageManager } from './storage/XmaxStorageManager';

/** SDK 的统一入口，负责创建实时、存储和媒体业务组件。 */
export class XmaxClient {

  /** 客户端使用的全局配置。 */
  readonly configuration: XmaxConfiguration;

  // 平台资源
  private readonly context?: common.UIAbilityContext;

  // 服务层组件
  private readonly apiService: ApiServicing;

  /**
   * 创建 SDK 客户端。
   *
   * @param configuration SDK 全局配置。
   * @param context 可选的平台页面上下文；创建依赖平台能力的 Manager 时必须提供。
   */
  constructor(
    configuration: XmaxConfiguration,
    context?: common.UIAbilityContext
  ) {
    this.configuration = configuration;
    this.context = context;
    this.apiService = new ApiService(configuration.apiKey);
  }

  /**
   * 创建实时生成业务 Manager。
   *
   * @param options 实时生成模型等业务配置。
   * @returns 可用于创建本地流、连接房间和控制生成流程的实时 Manager。
   */
  createRealtimeManager(options: RealtimeConfiguration): XmaxRealtimeManaging {
    if (this.context === undefined) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'UIAbilityContext is required to create a realtime manager on HarmonyOS'
      );
    }

    return new XmaxRealtimeManager(this.context, options, this.apiService);
  }

  /**
   * 创建文件存储 Manager。
   *
   * @returns 可用于上传和下载媒体文件的存储 Manager。
   */
  createStorageManager(): XmaxStorageManaging {
    this.configuration.validate();

    if (this.context === undefined) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'UIAbilityContext is required to create a storage manager on HarmonyOS'
      );
    }

    return new XmaxStorageManager(this.context.getApplicationContext(), this.apiService);
  }

  /**
   * 创建媒体业务规则服务。
   *
   * @returns 可用于计算模型输入尺寸的媒体服务。
   */
  createMediaService(): MediaServicing {
    return new MediaService();
  }
}
