//
//  RealtimeGenerationOptions.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { RealtimeContext } from './RealtimeContext';
import { RealtimeMediaStream } from './RealtimeMediaStream';

/** 生成请求的静态图片参数；图片地址必须可由服务端访问，并与本地输入保持相同比例。 */
export interface RealtimeGenerationParameters {
  /** 静态图片生成条件 */
  /** 是否从指定静态图片开始生成；省略时使用常规实时输入。 */
  readonly static_generate?: boolean;
  /** 静态输入图片地址；开启静态生成时必填。 */
  readonly static_image_path?: string;
}

/** 启动、更新或重新建立生成任务；重启仅替换任务，保留 RTC 连接和本地媒体流。 */
export interface RealtimeGenerationOptions {
  /** 输入媒体与生成条件 */
  /** 当前 Manager 创建的本地流；已连接时可省略。 */
  readonly localStream?: RealtimeMediaStream;
  /** 本次生成条件；省略时复用已缓存条件。 */
  readonly context?: RealtimeContext;

  /** 任务替换与图像修复 */
  /** true 时创建新任务，默认 false；静态任务确认后即可交互，普通任务还会等待首帧。 */
  readonly restart?: boolean;
  /** 是否启用原始人脸回贴，默认 false。 */
  readonly faceRestoration?: boolean;

  /** 静态图片输入 */
  /** 本次静态图配置；需同时提供 context，随其缓存，传入普通 context 可清除。 */
  readonly extraParams?: RealtimeGenerationParameters;
}
