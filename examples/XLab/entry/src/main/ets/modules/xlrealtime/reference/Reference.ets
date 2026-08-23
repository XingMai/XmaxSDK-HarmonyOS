export enum ReferenceUploadState {
  READY = 'ready',
  UPLOADING = 'uploading',
  FAILED = 'failed'
}

@Observed
export class Reference {
  readonly id: string;
  readonly categoryId: string;
  readonly title: string;
  readonly imageUrl?: string;
  remoteUrl?: string;
  readonly isAddAction: boolean;
  uploadState: ReferenceUploadState;
  constructor(
    id: string,
    categoryId: string,
    title: string,
    imageUrl?: string,
    remoteUrl?: string,
    isAddAction: boolean = false,
    uploadState: ReferenceUploadState = ReferenceUploadState.READY
  ) {
    this.id = id;
    this.categoryId = categoryId;
    this.title = title;
    this.imageUrl = imageUrl;
    this.remoteUrl = remoteUrl;
    this.isAddAction = isAddAction;
    this.uploadState = uploadState;
  }

  get isAvailableForGeneration(): boolean {
    return !this.isAddAction &&
      this.uploadState === ReferenceUploadState.READY &&
      this.remoteUrl !== undefined;
  }
}
