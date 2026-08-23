export class DownloadedFile {
  readonly filePath: string;
  readonly byteCount: number;

  constructor(
    filePath: string,
    byteCount: number
  ) {
    this.filePath = filePath;
    this.byteCount = byteCount;
  }
}
