export class StorageCredential {
  readonly accessKeyId: string;
  readonly secretAccessKey: string;
  readonly sessionToken: string;

  constructor(
    accessKeyId: string,
    secretAccessKey: string,
    sessionToken: string
  ) {
    this.accessKeyId = accessKeyId;
    this.secretAccessKey = secretAccessKey;
    this.sessionToken = sessionToken;
  }
}
