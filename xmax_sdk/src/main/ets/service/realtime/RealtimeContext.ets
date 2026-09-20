/** 去除首尾空白；空白串归一化为 undefined。 */
function normalizeOptional(text?: string): string | undefined {
  const trimmed: string | undefined = text?.trim();
  return trimmed !== undefined && trimmed.length > 0 ? trimmed : undefined;
}

export class RealtimeContext {
  readonly prompt: string;
  readonly referencePath?: string;
  readonly faceDetection?: boolean;

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
