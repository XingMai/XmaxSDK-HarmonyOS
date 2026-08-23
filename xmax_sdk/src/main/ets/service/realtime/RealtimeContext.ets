export class RealtimeContext {
  readonly prompt: string;
  readonly referencePath?: string;

  constructor(
    prompt: string,
    referencePath?: string
  ) {
    this.prompt = prompt.trim();
    const normalizedReferencePath = referencePath?.trim();
    this.referencePath = normalizedReferencePath?.length === 0
      ? undefined
      : normalizedReferencePath;
  }
}
