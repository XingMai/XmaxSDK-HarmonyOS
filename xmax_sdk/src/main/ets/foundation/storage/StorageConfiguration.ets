import { StorageCredential } from './StorageCredential';

export class StorageConfiguration {
  readonly bucket: string;
  readonly region: string;
  readonly endpoint: string;
  readonly credential: StorageCredential;

  constructor(
    bucket: string,
    region: string,
    endpoint: string,
    credential: StorageCredential
  ) {
    this.bucket = bucket;
    this.region = region;
    this.endpoint = endpoint;
    this.credential = credential;
  }
}
