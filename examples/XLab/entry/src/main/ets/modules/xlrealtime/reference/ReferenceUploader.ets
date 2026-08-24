import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
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
    const data: ArrayBuffer = this.readFile(filePath);
    const extension: string = this.imageExtension(filePath);
    const uploaded: XmaxUploadedFile = await this.client
      .createStorageManager()
      .uploadImage(
        data,
        `realtime_reference_${Date.now()}${extension}`,
        this.contentType(extension)
      );
    return uploaded.url;
  }

  private readFile(filePath: string): ArrayBuffer {
    const sourceFile: fileIo.File = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY);
    try {
      const data: ArrayBuffer = new ArrayBuffer(fileIo.statSync(sourceFile.fd).size);
      const bytesRead: number = fileIo.readSync(sourceFile.fd, data);
      return bytesRead === data.byteLength ? data : data.slice(0, bytesRead);
    } finally {
      fileIo.closeSync(sourceFile);
    }
  }

  private imageExtension(filePath: string): string {
    const normalizedPath: string = filePath.split('?')[0].toLowerCase();
    const extensions: string[] = [
      '.jpg', '.jpeg', '.png', '.gif', '.webp', '.heic', '.heif', '.bmp', '.tif', '.tiff', '.avif'
    ];
    for (let index: number = 0; index < extensions.length; index++) {
      if (normalizedPath.endsWith(extensions[index])) {
        return extensions[index];
      }
    }
    return '.jpg';
  }

  private contentType(extension: string): string {
    switch (extension) {
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      case '.heic':
      case '.heif':
        return 'image/heic';
      case '.bmp':
        return 'image/bmp';
      case '.tif':
      case '.tiff':
        return 'image/tiff';
      case '.avif':
        return 'image/avif';
      default:
        return 'image/jpeg';
    }
  }
}
