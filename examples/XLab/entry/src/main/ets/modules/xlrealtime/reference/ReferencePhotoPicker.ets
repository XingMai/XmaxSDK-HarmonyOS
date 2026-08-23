import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { util } from '@kit.ArkTS';

export class ReferencePhotoPicker {
  static async pickImage(context: common.UIAbilityContext): Promise<string | undefined> {
    const options = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = 1;

    const picker = new photoAccessHelper.PhotoViewPicker();
    const result = await picker.select(options);
    const sourceUri: string | undefined = result.photoUris[0];
    if (sourceUri === undefined) {
      return undefined;
    }
    return ReferencePhotoPicker.copyToCache(context, sourceUri);
  }

  private static copyToCache(context: common.UIAbilityContext, sourceUri: string): string {
    const directoryPath: string = `${context.cacheDir}/realtime_references`;
    if (!fileIo.accessSync(directoryPath)) {
      fileIo.mkdirSync(directoryPath);
    }
    const fileName: string = `${Date.now()}_${util.generateRandomUUID(true)}.jpg`;
    const destinationPath: string = `${directoryPath}/${fileName}`;
    const sourceFile = fileIo.openSync(sourceUri, fileIo.OpenMode.READ_ONLY);
    try {
      fileIo.copyFileSync(sourceFile.fd, destinationPath);
    } finally {
      fileIo.closeSync(sourceFile);
    }
    return destinationPath;
  }
}
