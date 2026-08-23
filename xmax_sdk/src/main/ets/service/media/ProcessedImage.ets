import { ImageSize } from './ImageSize';

export class ProcessedImage {
  readonly data: ArrayBuffer;
  readonly size: ImageSize;
  readonly contentType: string;

  constructor(
    data: ArrayBuffer,
    size: ImageSize,
    contentType: string
  ) {
    this.data = data;
    this.size = size;
    this.contentType = contentType;
  }
}
