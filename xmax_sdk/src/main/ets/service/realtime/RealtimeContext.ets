//
//  RealtimeContext.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/**
 * Trims text, normalizing blank values to undefined.
 *
 * @param text The optional text to trim and normalize.
 *
 * @returns The trimmed text, or undefined if absent or blank.
 */
function normalizeOptional(
  text?: string
): string | undefined {
  const trimmed: string | undefined = text?.trim();
  return trimmed !== undefined && trimmed.length > 0 ? trimmed : undefined;
}

/** The prompt, reference image, and face detection settings for generation. */
export class RealtimeContext {

  /** The prompt describing the desired generation result. */
  readonly prompt: string;

  /** The optional server-accessible reference image path. */
  readonly referencePath?: string;

  /** The optional face detection setting; omission uses the service default. */
  readonly faceDetection?: boolean;

  /**
   * Creates generation conditions.
   *
   * @param prompt The prompt describing the desired result.
   * @param referencePath The server-accessible reference image path; blank values are treated as
   * absent.
   * @param faceDetection Whether to enable face detection; omission uses the service default.
   */
  constructor(
    prompt: string,
    referencePath?: string,
    faceDetection?: boolean
  ) {
    this.prompt = prompt.trim();
    this.referencePath = normalizeOptional(referencePath);
    this.faceDetection = faceDetection;
  }
}
