import { common } from '@kit.AbilityKit';
import { XmaxClient, XmaxConfiguration, XmaxUploadedFile } from '@xmax/sdk';

export interface ReferenceUploading {
  uploadReference(filePath: string): Promise<string>;
}

export class ReferenceUploader implements ReferenceUploading {
  private readonly client: XmaxClient;

  constructor(context: common.UIAbilityContext, apiKey: string) {
    this.client = new XmaxClient(new XmaxConfiguration(apiKey), context);
  }

  async uploadReference(filePath: string): Promise<string> {
    const uploaded: XmaxUploadedFile = await this.client
      .createStorageManager()
      .uploadImageFileWithSafetyCheck(filePath);
    return uploaded.url;
  }
}
