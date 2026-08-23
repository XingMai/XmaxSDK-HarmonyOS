import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import {
  promptAction,
  router
} from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { media } from '@kit.MediaKit';
import {
  XmaxClient,
  XmaxConfiguration,
  XmaxStorageManaging,
  XmaxStorageProgress,
  XmaxUploadedFile,
  XMAX_SDK_VERSION
} from '@xmax/sdk';
import { XLabConfiguration } from '../xlrealtime/config/XLabConfiguration';

enum StorageMediaKind {
  IMAGE = 'image',
  VIDEO = 'video'
}

@Component
struct StorageTopBar {
  onBack: () => void = (): void => {};

  build() {
    Row() {
      Button({ type: ButtonType.Normal }) {
        Image($r('app.media.realtime_nav_back'))
          .width(32)
          .height(32)
          .shadow({ radius: 2, color: '#80000000', offsetX: 0, offsetY: 1 })
      }
      .width(44)
      .height(44)
      .padding(0)
      .backgroundColor(Color.Transparent)
      .accessibilityText('返回首页')
      .onClick((): void => {
        this.onBack();
      })

      Column() {
        Text('存储服务')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#F4F7FB')

        Text('EXAMPLE / HARMONYOS')
          .margin({ top: 3 })
          .fontSize(8)
          .fontColor('#B8F5B86C')
          .letterSpacing(1)
      }
      .margin({ left: 8 })
      .alignItems(HorizontalAlign.Start)

      Blank()

      Text(`v${XMAX_SDK_VERSION}`)
        .height(25)
        .padding({ left: 9, right: 9 })
        .fontSize(8)
        .fontWeight(FontWeight.Bold)
        .fontColor('#F5B86C')
        .textAlign(TextAlign.Center)
        .backgroundColor('#24F5B86C')
        .borderRadius(13)
        .border({ width: 1, color: '#4AF5B86C' })
    }
    .width('100%')
    .height(72)
    .padding({ left: 8, right: 18, top: 12 })
  }
}

@Entry
@Component
struct StoragePage {
  private readonly videoController: VideoController = new VideoController();
  private readonly scroller: Scroller = new Scroller();
  @State private selectedFilePath: string = '';
  @State private selectedSourceUri: string = '';
  @State private selectedMediaKind: StorageMediaKind = StorageMediaKind.IMAGE;
  @State private selectedFileSize: number = 0;
  @State private selectedResolution: string = '';
  @State private isPicking: boolean = false;
  @State private isUploading: boolean = false;
  @State private activeUploadUsesSafetyCheck: boolean = false;
  @State private uploadProgress: number = 0;
  @State private uploadElapsedMs: number = 0;
  @State private uploadedUrl: string = '';
  @State private errorMessage: string = '';

  private async selectMedia(): Promise<void> {
    if (this.isPicking || this.isUploading) {
      return;
    }

    this.isPicking = true;
    try {
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_VIDEO_TYPE;
      options.maxSelectNumber = 1;

      const picker = new photoAccessHelper.PhotoViewPicker();
      const result = await picker.select(options);
      const sourceUri: string | undefined = result.photoUris[0];
      if (sourceUri === undefined || sourceUri.trim().length === 0) {
        return;
      }

      const kind: StorageMediaKind = this.mediaKind(sourceUri);
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const localPath: string = this.copyToCache(context, sourceUri, kind);
      this.selectedFilePath = localPath;
      this.selectedSourceUri = sourceUri;
      this.selectedMediaKind = kind;
      this.selectedFileSize = fileIo.statSync(localPath).size;
      this.selectedResolution = await this.readResolution(localPath, kind);
      this.uploadProgress = 0;
      this.uploadElapsedMs = 0;
      this.uploadedUrl = '';
      this.errorMessage = '';
    } catch (error) {
      this.errorMessage = this.errorText(error, '读取文件失败，请重试');
    } finally {
      this.isPicking = false;
    }
  }

  private mediaKind(sourceUri: string): StorageMediaKind {
    const normalized: string = sourceUri.split('?')[0].toLowerCase();
    const videoExtensions: string[] = [
      '.mp4', '.mov', '.m4v', '.webm', '.avi', '.mkv', '.3gp', '.3g2', '.ts'
    ];
    for (let index: number = 0; index < videoExtensions.length; index++) {
      if (normalized.endsWith(videoExtensions[index])) {
        return StorageMediaKind.VIDEO;
      }
    }
    return StorageMediaKind.IMAGE;
  }

  private copyToCache(
    context: common.UIAbilityContext,
    sourceUri: string,
    kind: StorageMediaKind
  ): string {
    const directoryPath: string = `${context.cacheDir}/storage_playground`;
    if (!fileIo.accessSync(directoryPath)) {
      fileIo.mkdirSync(directoryPath);
    }

    const extension: string = this.mediaExtension(sourceUri, kind);
    const destinationPath: string = `${directoryPath}/${Date.now()}_` +
      `${util.generateRandomUUID(true)}${extension}`;
    const sourceFile = fileIo.openSync(sourceUri, fileIo.OpenMode.READ_ONLY);
    try {
      fileIo.copyFileSync(sourceFile.fd, destinationPath);
    } finally {
      fileIo.closeSync(sourceFile);
    }
    return destinationPath;
  }

  private mediaExtension(sourceUri: string, kind: StorageMediaKind): string {
    const normalized: string = sourceUri.split('?')[0].toLowerCase();
    const extensions: string[] = kind === StorageMediaKind.IMAGE ?
      ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.heic', '.heif', '.bmp', '.tif', '.tiff', '.avif'] :
      ['.mp4', '.mov', '.m4v', '.webm', '.avi', '.mkv', '.3gp', '.3g2', '.ts'];
    for (let index: number = 0; index < extensions.length; index++) {
      if (normalized.endsWith(extensions[index])) {
        return extensions[index];
      }
    }
    return kind === StorageMediaKind.IMAGE ? '.jpg' : '.mp4';
  }

  private async readResolution(
    filePath: string,
    kind: StorageMediaKind
  ): Promise<string> {
    try {
      return kind === StorageMediaKind.IMAGE ?
        await this.readImageResolution(filePath) :
        await this.readVideoResolution(filePath);
    } catch (_error) {
      return '';
    }
  }

  private async readImageResolution(filePath: string): Promise<string> {
    const sourceFile: fileIo.File = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY);
    let imageSource: image.ImageSource | undefined = undefined;
    try {
      imageSource = image.createImageSource(sourceFile.fd);
      if (imageSource === undefined) {
        return '';
      }

      const info: image.ImageInfo = await imageSource.getImageInfo();
      return this.formatResolution(info.size.width, info.size.height);
    } finally {
      try {
        if (imageSource !== undefined) {
          await imageSource.release();
        }
      } finally {
        fileIo.closeSync(sourceFile);
      }
    }
  }

  private async readVideoResolution(filePath: string): Promise<string> {
    const sourceFile: fileIo.File = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY);
    let extractor: media.AVMetadataExtractor | null = null;
    try {
      extractor = await media.createAVMetadataExtractor();
      extractor.fdSrc = {
        fd: sourceFile.fd,
        offset: 0,
        length: fileIo.statSync(sourceFile.fd).size
      };

      const metadata: media.AVMetadata = await extractor.fetchMetadata();
      const width: number = Number.parseInt(metadata.videoWidth ?? '');
      const height: number = Number.parseInt(metadata.videoHeight ?? '');
      const rotation: number = Number.parseInt(metadata.videoOrientation ?? '0');
      const normalizedRotation: number = Number.isFinite(rotation) ?
        ((rotation % 360) + 360) % 360 : 0;
      return normalizedRotation === 90 || normalizedRotation === 270 ?
        this.formatResolution(height, width) :
        this.formatResolution(width, height);
    } finally {
      try {
        if (extractor !== null) {
          await extractor.release();
        }
      } finally {
        fileIo.closeSync(sourceFile);
      }
    }
  }

  private formatResolution(width: number, height: number): string {
    if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) {
      return '';
    }
    return `${width} × ${height}`;
  }

  private async uploadSelectedFile(withSafetyCheck: boolean = false): Promise<void> {
    if (this.selectedFilePath.length === 0 || this.isUploading) {
      return;
    }

    this.isUploading = true;
    this.activeUploadUsesSafetyCheck = withSafetyCheck;
    this.uploadProgress = 0;
    this.uploadElapsedMs = 0;
    this.uploadedUrl = '';
    this.errorMessage = '';
    const uploadStartedAt: number = Date.now();

    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const client = new XmaxClient(
        new XmaxConfiguration(XLabConfiguration.currentApiKey()),
        context
      );
      const progress = (value: XmaxStorageProgress): void => {
        this.uploadProgress = value.fractionCompleted;
      };
      const storageManager: XmaxStorageManaging = client.createStorageManager();
      const uploaded: XmaxUploadedFile = this.selectedMediaKind === StorageMediaKind.IMAGE ?
        withSafetyCheck ? await storageManager.uploadImageFileWithSafetyCheck(
          this.selectedFilePath,
          undefined,
          progress
        ) : await storageManager.uploadImageFile(
          this.selectedFilePath,
          undefined,
          progress
        ) : await storageManager.uploadVideoFile(this.selectedFilePath, undefined, progress);

      this.uploadProgress = 1;
      this.uploadedUrl = uploaded.url;
      this.uploadElapsedMs = Date.now() - uploadStartedAt;
      setTimeout((): void => {
        this.scroller.scrollEdge(Edge.Bottom, { velocity: 1200 });
      }, 100);
    } catch (error) {
      this.errorMessage = this.errorText(error, '上传失败，请检查 API Key 和网络后重试');
    } finally {
      this.isUploading = false;
    }
  }

  private async copyUploadedUrl(): Promise<void> {
    if (this.uploadedUrl.length === 0) {
      return;
    }

    try {
      const data = pasteboard.createData(
        pasteboard.MIMETYPE_TEXT_PLAIN,
        this.uploadedUrl
      );
      await pasteboard.getSystemPasteboard().setData(data);
      promptAction.showToast({ message: '地址已复制' });
    } catch (_error) {
      promptAction.showToast({ message: '复制失败，请重试' });
    }
  }

  private errorText(error: Object, fallback: string): string {
    if (error instanceof Error && error.message.trim().length > 0) {
      return error.message;
    }
    return fallback;
  }

  private formattedFileSize(): string {
    if (this.selectedFileSize <= 0) {
      return '0 B';
    }
    if (this.selectedFileSize < 1024) {
      return `${this.selectedFileSize} B`;
    }
    if (this.selectedFileSize < 1024 * 1024) {
      return `${(this.selectedFileSize / 1024).toFixed(1)} KB`;
    }
    return `${(this.selectedFileSize / (1024 * 1024)).toFixed(1)} MB`;
  }

  private selectedTypeText(): string {
    return this.selectedMediaKind === StorageMediaKind.IMAGE ? '图片' : '视频';
  }

  private formattedUploadElapsed(): string {
    if (this.uploadElapsedMs <= 0) {
      return '--';
    }
    if (this.uploadElapsedMs < 1000) {
      return `${this.uploadElapsedMs} ms`;
    }
    return `${(this.uploadElapsedMs / 1000).toFixed(2)} s`;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width(280)
        .height(280)
        .position({ right: -150, top: -70 })
        .backgroundColor('#32F5B86C')
        .borderRadius(140)
        .blur(86)

      Column()
        .width(180)
        .height(180)
        .position({ left: -130, top: 310 })
        .backgroundColor('#18C67A35')
        .borderRadius(90)
        .blur(76)

      Column() {
        StorageTopBar({
          onBack: (): void => {
            router.back();
          }
        })

        Scroll(this.scroller) {
          Column() {
            Column() {
            Row() {
              Row({ space: 7 }) {
                Column()
                  .width(6)
                  .height(6)
                  .backgroundColor('#F5B86C')
                  .borderRadius(3)

                Text('STORAGE PIPELINE')
                  .fontSize(9)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#F5B86C')
                  .letterSpacing(1)
              }

              Blank()

              Text('READY')
                .height(23)
                .padding({ left: 9, right: 9 })
                .fontSize(8)
                .fontWeight(FontWeight.Bold)
                .fontColor('#F5B86C')
                .textAlign(TextAlign.Center)
                .backgroundColor('#20F5B86C')
                .borderRadius(12)
            }
            .width('100%')

            Text('把本地媒体交给 XmaxSDK')
              .width('100%')
              .margin({ top: 13 })
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#F4EEE6')

            Text('选择图片或视频，上传后获取可直接使用的远程地址。')
              .width('100%')
              .margin({ top: 7 })
              .fontSize(10)
              .fontColor('#8E8377')
              .lineHeight(17)

            Row() {
              Text('LOCAL FILE')
                .fontSize(8)
                .fontWeight(FontWeight.Bold)
                .fontColor('#9A8B7A')

              Text('—')
                .margin({ left: 8, right: 8 })
                .fontSize(9)
                .fontColor('#66513A')

              Text('XMAX SDK')
                .fontSize(8)
                .fontWeight(FontWeight.Bold)
                .fontColor('#F5B86C')

              Text('—')
                .margin({ left: 8, right: 8 })
                .fontSize(9)
                .fontColor('#66513A')

              Text('REMOTE URL')
                .fontSize(8)
                .fontWeight(FontWeight.Bold)
                .fontColor('#9A8B7A')
            }
            .width('100%')
            .margin({ top: 15 })
          }
          .width('100%')
          .padding(17)
          .alignItems(HorizontalAlign.Start)
          .linearGradient({
            angle: 135,
            colors: [['#F01D1711', 0.0], ['#E80F1115', 1.0]]
          })
          .borderRadius(18)
          .border({ width: 1, color: '#3DF5B86C' })
          .shadow({ radius: 20, color: '#65000000', offsetY: 9 })

          Column() {
            Row() {
              Text('01')
                .width(28)
                .height(22)
                .fontSize(8)
                .fontWeight(FontWeight.Bold)
                .fontColor('#F5B86C')
                .textAlign(TextAlign.Center)
                .backgroundColor('#20F5B86C')
                .borderRadius(11)
                .border({ width: 1, color: '#45F5B86C' })

              Text('文件预览')
                .margin({ left: 9 })
                .fontSize(13)
                .fontWeight(FontWeight.Bold)
                .fontColor('#F2ECE4')

              Blank()

              if (this.selectedFilePath.length > 0) {
                Button('重新上传')
                  .width(66)
                  .height(28)
                  .padding(0)
                  .fontSize(9)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#F5B86C')
                  .backgroundColor('#12F5B86C')
                  .borderRadius(9)
                  .border({ width: 1, color: '#38F5B86C' })
                  .enabled(!this.isPicking && !this.isUploading)
                  .onClick((): void => {
                    void this.selectMedia();
                  })
              } else {
                Text('点击选择')
                  .fontSize(9)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#6E6257')
              }
            }
            .width('100%')
            .margin({ bottom: 10 })

            if (this.selectedFilePath.length > 0 &&
              this.selectedMediaKind === StorageMediaKind.VIDEO) {
              Text('视频生成暂不支持安全检测')
                .width('100%')
                .margin({ bottom: 10 })
                .fontSize(9)
                .fontColor('#596678')
            }

            if (this.selectedFilePath.length === 0) {
              Column() {
                Text('+')
                  .width(42)
                  .height(42)
                  .fontSize(22)
                  .fontColor('#F5B86C')
                  .textAlign(TextAlign.Center)
                  .backgroundColor('#18F5B86C')
                  .borderRadius(21)
                  .border({ width: 1, color: '#3DF5B86C' })

                Text(this.isPicking ? '正在打开媒体库' : '点击选择图片或视频')
                  .margin({ top: 11 })
                  .fontSize(11)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#9D9185')

                Text('IMAGE  /  VIDEO')
                  .margin({ top: 5 })
                  .fontSize(8)
                  .fontColor('#62584E')
                  .letterSpacing(0.8)
              }
                .width('100%')
                .height(176)
                .justifyContent(FlexAlign.Center)
                .backgroundColor('#900B0C0F')
                .borderRadius(14)
                .border({ width: 1, color: '#26F5B86C' })
                .enabled(!this.isPicking && !this.isUploading)
                .onClick((): void => {
                  void this.selectMedia();
                })
            } else if (this.selectedMediaKind === StorageMediaKind.IMAGE) {
              Image(this.selectedSourceUri)
                .width('100%')
                .height(176)
                .objectFit(ImageFit.Contain)
                .backgroundColor('#900B0C0F')
                .border({ width: 1, color: '#26F5B86C' })
            } else {
              Video({
                src: this.selectedSourceUri,
                controller: this.videoController
              })
                .width('100%')
                .height(176)
                .autoPlay(true)
                .controls(false)
                .loop(true)
                .objectFit(ImageFit.Contain)
                .backgroundColor('#900B0C0F')
                .border({ width: 1, color: '#35F5B86C' })
            }

            Row({ space: 8 }) {
              Column() {
                Text('type')
                  .fontSize(8)
                  .fontColor('#6E6257')

                Text(this.selectedFilePath.length > 0 ? this.selectedTypeText() : '--')
                  .margin({ top: 4 })
                  .fontSize(10)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.selectedFilePath.length > 0 ? '#E7DED4' : '#5C534A')
              }
              .layoutWeight(1)
              .height(51)
              .padding({ left: 11 })
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Start)
              .backgroundColor('#8A0C0D10')
              .borderRadius(10)

              Column() {
                Text('resolution')
                  .fontSize(8)
                  .fontColor('#6E6257')

                Text(this.selectedFilePath.length > 0 && this.selectedResolution.length > 0 ?
                  this.selectedResolution : '--')
                  .margin({ top: 4 })
                  .fontSize(9)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#B9AA9B')
              }
              .layoutWeight(1)
              .height(51)
              .padding({ left: 11 })
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Start)
              .backgroundColor('#8A0C0D10')
              .borderRadius(10)

              Column() {
                Text('size')
                  .fontSize(8)
                  .fontColor('#6E6257')

                Text(this.selectedFilePath.length > 0 ? this.formattedFileSize() : '--')
                  .margin({ top: 4 })
                  .fontSize(9)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#B9AA9B')
              }
              .layoutWeight(1)
              .height(51)
              .padding({ left: 11 })
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Start)
              .backgroundColor('#8A0C0D10')
              .borderRadius(10)
            }
            .width('100%')
            .margin({ top: 10 })

            if (this.isUploading) {
              Row() {
                Text(`上传中 ${Math.round(this.uploadProgress * 100)}%`)
                  .fontSize(10)
                  .fontColor('#F5B86C')

                Blank()

                Text(this.selectedMediaKind === StorageMediaKind.IMAGE ?
                  this.activeUploadUsesSafetyCheck ? '包含内容安全检查' : '正在上传图片' : '正在上传视频')
                  .fontSize(9)
                  .fontColor('#657386')
              }
              .width('100%')
              .margin({ top: 16, bottom: 7 })

              Progress({ value: this.uploadProgress * 100, total: 100, type: ProgressType.Linear })
                .width('100%')
                .height(5)
                .color('#F5B86C')
                .backgroundColor('#24F5B86C')
                .borderRadius(3)
            }

            if (this.selectedFilePath.length > 0) {
              if (this.selectedMediaKind === StorageMediaKind.IMAGE) {
                Row({ space: 10 }) {
                  Button(this.isUploading && this.activeUploadUsesSafetyCheck ?
                    '正在检测上传' : '安全检测上传')
                    .layoutWeight(1)
                    .height(38)
                    .fontSize(11)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#F5B86C')
                    .backgroundColor('#14F5B86C')
                    .borderRadius(12)
                    .border({ width: 1, color: '#48F5B86C' })
                    .enabled(!this.isUploading)
                    .opacity(this.isUploading ? 0.6 : 1)
                    .onClick((): void => {
                      void this.uploadSelectedFile(true);
                    })

                  Button(this.isUploading && !this.activeUploadUsesSafetyCheck ?
                    '正在上传' : '普通上传')
                    .layoutWeight(1)
                    .height(38)
                    .fontSize(11)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#F5B86C')
                    .backgroundColor('#14F5B86C')
                    .borderRadius(12)
                    .border({ width: 1, color: '#48F5B86C' })
                    .enabled(!this.isUploading)
                    .opacity(this.isUploading ? 0.6 : 1)
                    .onClick((): void => {
                      void this.uploadSelectedFile(false);
                    })
                }
                .width('100%')
                .margin({ top: 16 })
              } else {
                Button(this.isUploading ? '正在上传' : '上传并获取地址')
                  .width('100%')
                  .height(38)
                  .margin({ top: 16 })
                  .fontSize(11)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#F5B86C')
                  .backgroundColor('#14F5B86C')
                  .borderRadius(12)
                  .border({ width: 1, color: '#48F5B86C' })
                  .enabled(!this.isUploading)
                  .opacity(this.isUploading ? 0.6 : 1)
                  .onClick((): void => {
                    void this.uploadSelectedFile(false);
                  })
              }
            }
          }
          .width('100%')
          .margin({ top: 14 })
          .padding(17)
          .alignItems(HorizontalAlign.Start)
          .linearGradient({
            angle: 135,
            colors: [['#ED1B1712', 0.0], ['#E8111216', 1.0]]
          })
          .borderRadius(18)
          .border({ width: 1, color: '#2EF5B86C' })
          .shadow({ radius: 16, color: '#52000000', offsetY: 7 })

          if (this.errorMessage.length > 0) {
            Text(this.errorMessage)
              .width('100%')
              .margin({ top: 12 })
              .padding(12)
              .fontSize(10)
              .fontColor('#FFB5B5')
              .lineHeight(16)
              .backgroundColor('#28FF5F68')
              .borderRadius(11)
              .border({ width: 1, color: '#38FF6B72' })
          }

          if (this.uploadedUrl.length > 0) {
            Column() {
              Row() {
                Text('02')
                  .width(28)
                  .height(22)
                  .fontSize(8)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#F5B86C')
                  .textAlign(TextAlign.Center)
                  .backgroundColor('#20F5B86C')
                  .borderRadius(11)
                  .border({ width: 1, color: '#45F5B86C' })

                Text('上传结果')
                  .margin({ left: 9 })
                  .fontSize(13)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#F2ECE4')

                Blank()

                Text('SUCCESS')
                  .width(66)
                  .height(28)
                  .fontSize(9)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#F5B86C')
                  .textAlign(TextAlign.Center)
                  .backgroundColor('#12F5B86C')
                  .borderRadius(9)
                  .border({ width: 1, color: '#38F5B86C' })
              }
              .width('100%')

              Row() {
                Text('上传耗时')
                  .fontSize(10)
                  .fontColor('#718095')

                Blank()

                Text(this.formattedUploadElapsed())
                  .fontSize(10)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.uploadElapsedMs > 0 ? '#F5B86C' : '#665C52')
              }
              .width('100%')
              .margin({ top: 15 })

              Text('REMOTE URL')
                .width('100%')
                .margin({ top: 14 })
                .fontSize(8)
                .fontWeight(FontWeight.Bold)
                .fontColor('#667589')
                .letterSpacing(0.8)

              Text(this.uploadedUrl.length > 0 ?
                this.uploadedUrl : '上传完成后，远程地址会显示在这里。')
                .width('100%')
                .margin({ top: 7 })
                .padding(11)
                .fontSize(9)
                .fontColor(this.uploadedUrl.length > 0 ? '#CDBEAF' : '#665C52')
                .lineHeight(15)
                .backgroundColor('#950B0C0F')
                .borderRadius(11)
                .border({ width: 1, color: '#20F5B86C' })

              Button(this.uploadedUrl.length > 0 ? '复制地址' : '暂无可复制地址')
                .width('100%')
                .height(38)
                .margin({ top: 12 })
                .fontSize(11)
                .fontWeight(FontWeight.Bold)
                .fontColor('#F5B86C')
                .backgroundColor('#14F5B86C')
                .borderRadius(12)
                .border({ width: 1, color: '#48F5B86C' })
                .enabled(this.uploadedUrl.length > 0)
                .opacity(this.uploadedUrl.length > 0 ? 1 : 0.42)
                .onClick((): void => {
                  void this.copyUploadedUrl();
                })
            }
            .width('100%')
            .margin({ top: 14 })
            .padding(17)
            .alignItems(HorizontalAlign.Start)
            .linearGradient({
              angle: 135,
              colors: [['#ED1B1712', 0.0], ['#E8111216', 1.0]]
            })
            .borderRadius(18)
            .border({
              width: 1,
              color: this.uploadedUrl.length > 0 ? '#58F5B86C' : '#2EF5B86C'
            })
            .shadow({ radius: 18, color: '#60000000', offsetY: 8 })
          }

          }
          .width('100%')
          .padding({ left: 18, right: 18, top: 12 })
          .alignItems(HorizontalAlign.Start)
          .justifyContent(FlexAlign.Start)
        }
        .width('100%')
        .layoutWeight(1)
        .align(Alignment.TopStart)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: false })
        .expandSafeArea(
          [SafeAreaType.SYSTEM],
          [SafeAreaEdge.BOTTOM]
        )
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#090A0C')
    .expandSafeArea(
      [SafeAreaType.SYSTEM],
      [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]
    )
  }
}
