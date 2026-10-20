//
//  RealtimeContext.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { RealtimeGenerationParameters } from './RealtimeGenerationOptions';

/**
 * 去除首尾空白；空白串归一化为 undefined。
 *
 * @param text 需要去除首尾空白并规范化的可选文本。
 * @returns 去除首尾空白后的文本；未设置或仅含空白时返回 undefined。
 */
function normalizeOptional(text?: string): string | undefined {
  const trimmed: string | undefined = text?.trim();
  return trimmed !== undefined && trimmed.length > 0 ? trimmed : undefined;
}

/** 配置生成提示词、参考图路径、人脸检测和静态图片输入。 */
export class RealtimeContext {

  /** 生成提示与参考条件 */
  readonly prompt: string;
  readonly referencePath?: string;
  readonly faceDetection?: boolean;

  /** 静态图生成条件；省略时使用常规实时输入。 */
  readonly extraParams?: RealtimeGenerationParameters;

  /**
   * 创建生成上下文。
   *
   * @param prompt 描述期望生成效果的提示词。
   * @param referencePath 服务端可访问的参考图路径；空白内容按未设置处理。
   * @param faceDetection 是否启用人脸检测；省略时使用服务默认行为。
   * @param extraParams 静态图生成参数；省略时不启用静态生成。
   * @returns 新建的 RealtimeContext 实例。
   */
  constructor(
    prompt: string,
    referencePath?: string,
    faceDetection?: boolean,
    extraParams?: RealtimeGenerationParameters
  ) {
    this.prompt = prompt.trim();
    this.referencePath = normalizeOptional(referencePath);
    this.faceDetection = faceDetection;
    this.extraParams = extraParams === undefined ? undefined : {
      static_generate: extraParams.static_generate,
      static_image_path: normalizeOptional(extraParams.static_image_path)
    };
  }
}
