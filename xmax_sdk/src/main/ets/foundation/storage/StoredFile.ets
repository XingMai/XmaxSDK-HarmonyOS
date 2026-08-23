export class StoredFile {
  readonly url: string;
  readonly objectKey: string;
  readonly etag?: string;

  constructor(
    url: string,
    objectKey: string,
    etag?: string
  ) {
    this.url = url;
    this.objectKey = objectKey;
    this.etag = etag;
  }
}
