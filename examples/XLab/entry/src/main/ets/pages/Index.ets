import {
  promptAction,
  router
} from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { systemShare } from '@kit.ShareKit';
import { RealtimeModel, XMAX_SDK_VERSION } from '@xmax/sdk';
import { XLabConfiguration } from '../modules/xlrealtime/config/XLabConfiguration';
import { XLabModelSelection } from '../modules/xlrealtime/config/XLabModelSelection';

@Component
struct ConsoleTag {
  @Prop label: string = '';
  @Prop tagColor: string = '#8EF0C8';
  @Prop tagBackground: string = '#168EF0C8';

  build() {
    Text(this.label)
      .height(26)
      .padding({ left: 11, right: 11 })
      .fontSize(9)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.tagColor)
      .letterSpacing(0.8)
      .textAlign(TextAlign.Center)
      .backgroundColor(this.tagBackground)
      .borderRadius(13)
      .border({ width: 1, color: '#30FFFFFF' })
  }
}

@Component
struct RuntimeMetric {
  @Prop label: string = '';
  @Prop value: string = '';

  build() {
    Column() {
      Text(this.label)
        .width('100%')
        .fontSize(8)
        .fontWeight(FontWeight.Bold)
        .fontColor('#62FFFFFF')
        .letterSpacing(1)

      Text(this.value)
        .width('100%')
        .margin({ top: 7 })
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor('#E8EDF5')
        .maxLines(1)
    }
    .layoutWeight(1)
    .height(66)
    .padding({ left: 12, right: 10, top: 12, bottom: 10 })
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#B30E141C')
    .borderRadius(13)
    .border({ width: 1, color: '#18FFFFFF' })
  }
}

@Component
struct ModelRegistryCard {
  @Prop selectedModel: string = RealtimeModel.X2_0;
  @Prop apiKey: string = '';
  onSelect: (model: RealtimeModel) => void = (_model: RealtimeModel): void => {};
  onApiKeyChange: (apiKey: string) => void = (_apiKey: string): void => {};

  private async openApiKeyApplicationPage(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await context.openLink('https://platform.xmaxai.com/api-keys');
    } catch (_error) {
      promptAction.showToast({ message: '无法打开申请页面，请稍后重试' });
    }
  }

  build() {
    Column() {
      Row() {
        Text('选择你的模型')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor('#E9EDF3')

        Blank()

        Text('1 MODEL')
          .fontSize(8)
          .fontColor('#70FFFFFF')
          .letterSpacing(0.8)
      }
      .width('100%')

      Column() {
        Row() {
          Text('API KEY')
            .fontSize(8)
            .fontWeight(FontWeight.Bold)
            .fontColor('#7E8A9A')
            .letterSpacing(0.9)
        }
        .width('100%')

        TextInput({
          text: this.apiKey,
          placeholder: '输入 Xmax API Key'
        })
          .width('100%')
          .height(40)
          .margin({ top: 8 })
          .padding({ left: 12, right: 8 })
          .type(InputType.Password)
          .showPasswordIcon(true)
          .passwordIcon({
            onIconSrc: $r('app.media.api_key_hidden'),
            offIconSrc: $r('app.media.api_key_visible')
          })
          .fontSize(10)
          .fontColor('#D6DEE9')
          .placeholderFont({ size: 10 })
          .placeholderColor('#50607080')
          .backgroundColor('#66080C12')
          .borderRadius(10)
          .border({ width: 1, color: '#1CFFFFFF' })
          .onChange((value: string): void => {
            this.onApiKeyChange(value);
          })

        Row({ space: 4 }) {
          Text('还没有 API Key？')
            .fontSize(9)
            .fontColor('#60708090')

          Text('前往 Xmax 开放平台申请')
            .fontSize(9)
            .fontColor('#A08EF0C8')
            .onClick((): void => {
              void this.openApiKeyApplicationPage();
            })
        }
        .width('100%')
        .margin({ top: 7 })
      }
      .width('100%')
      .margin({ top: 14 })
      .padding({ left: 10, right: 10, top: 10, bottom: 11 })
      .alignItems(HorizontalAlign.Start)
      .backgroundColor('#42080C12')
      .borderRadius(12)
      .border({ width: 1, color: '#12FFFFFF' })

      Divider()
        .margin({ top: 12, bottom: 4 })
        .color('#18FFFFFF')

      Row() {
        Text('◆')
          .fontSize(7)
          .fontColor(this.selectedModel === RealtimeModel.X2_0 ? '#8EF0C8' : '#66FFFFFF')

        Column() {
          Text('X2.0')
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.selectedModel === RealtimeModel.X2_0 ? '#F0F2F5' : '#A8B0BC')

          Text('RealtimeModel.X2_0')
          .margin({ top: 3 })
          .fontSize(8)
          .fontColor(this.selectedModel === RealtimeModel.X2_0 ? '#70FFFFFF' : '#4FFFFFFF')
        }
        .margin({ left: 10 })
        .alignItems(HorizontalAlign.Start)

        Blank()

        ConsoleTag({
          label: this.selectedModel === RealtimeModel.X2_0 ? 'ACTIVE' : 'SELECT',
          tagColor: this.selectedModel === RealtimeModel.X2_0 ? '#8EF0C8' : '#80FFFFFF',
          tagBackground: this.selectedModel === RealtimeModel.X2_0 ? '#168EF0C8' : '#0AFFFFFF'
        })
      }
      .width('100%')
      .height(56)
      .padding({ left: 10, right: 8 })
      .backgroundColor(this.selectedModel === RealtimeModel.X2_0 ? '#108EF0C8' : '#00000000')
      .borderRadius(10)
      .onClick((): void => {
        this.onSelect(RealtimeModel.X2_0);
      })
    }
    .width('100%')
    .padding(18)
    .alignItems(HorizontalAlign.Start)
    .linearGradient({
      angle: 135,
      colors: [['#E8121B19', 0.0], ['#E80D1218', 1.0]]
    })
    .borderRadius(17)
    .border({ width: 1, color: '#258EF0C8' })
    .shadow({ radius: 18, color: '#70000000', offsetY: 8 })
  }
}

@Component
struct PipelineCard {
  @Prop sequence: string = '';
  @Prop modeId: string = '';
  @Prop status: string = '';
  @Prop statusColor: string = '#8EF0C8';
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop capability: string = '';
  @Prop isReady: boolean = false;
  onOpen: () => void = (): void => {};

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width(112)
        .height(112)
        .position({ right: -38, top: -46 })
        .backgroundColor(this.statusColor)
        .borderRadius(56)
        .opacity(0.1)

      Column()
        .width(3)
        .height(70)
        .position({ left: 0, top: 22 })
        .backgroundColor(this.statusColor)
        .borderRadius({ topRight: 2, bottomRight: 2 })

      Text(this.sequence)
        .position({ right: 17, top: 5 })
        .fontSize(54)
        .fontWeight(FontWeight.Bold)
        .fontColor('#08FFFFFF')

      Column() {
        Row() {
          Row({ space: 8 }) {
            Column()
              .width(7)
              .height(7)
              .backgroundColor(this.statusColor)
              .borderRadius(4)
              .shadow({ radius: 7, color: this.statusColor })

            Text(this.modeId)
              .fontSize(9)
              .fontWeight(FontWeight.Bold)
              .fontColor('#9AA7B7')
              .letterSpacing(0.8)
          }

          Blank()

          Row({ space: 6 }) {
            Text('●')
              .fontSize(7)
              .fontColor(this.statusColor)

            Text(this.status)
              .fontSize(9)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.statusColor)
              .letterSpacing(0.8)
          }
            .height(25)
            .padding({ left: 9, right: 10 })
            .backgroundColor('#0CFFFFFF')
            .borderRadius(13)
            .border({ width: 1, color: '#18FFFFFF' })
        }
        .width('100%')

        Text(this.title)
          .width('100%')
          .margin({ top: 17 })
          .fontSize(21)
          .fontWeight(FontWeight.Bold)
          .fontColor('#F4F7FB')

        Text(this.subtitle)
          .width('100%')
          .margin({ top: 7 })
          .fontSize(12)
          .fontColor('#8E9AA9')
          .lineHeight(18)
          .maxLines(2)

        Row() {
          Row() {
            Text(this.capability)
              .fontSize(9)
              .fontWeight(FontWeight.Medium)
              .fontColor('#B8C3D1')
              .maxLines(1)
          }
            .layoutWeight(1)
            .height(36)
            .padding({ left: 11, right: 8 })
            .alignItems(VerticalAlign.Center)
            .backgroundColor('#66080C12')
            .borderRadius(10)
            .border({ width: 1, color: '#16FFFFFF' })

          if (this.isReady) {
            Row() {
              Text('运行')
                .fontSize(11)
                .fontWeight(FontWeight.Bold)
                .fontColor('#08110E')
            }
              .margin({ left: 10 })
              .width(82)
              .height(36)
              .justifyContent(FlexAlign.Center)
              .alignItems(VerticalAlign.Center)
              .backgroundColor(this.statusColor)
              .borderRadius(10)
              .shadow({ radius: 10, color: '#40000000', offsetY: 4 })
          }
        }
        .width('100%')
        .margin({ top: 18 })
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 17, bottom: 17 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .backgroundColor('#E6111720')
    .linearGradient({
      angle: 135,
      colors: [['#F0141B25', 0.0], ['#F00C1118', 1.0]]
    })
    .borderRadius(18)
    .border({ width: 1, color: '#22FFFFFF' })
    .shadow({
      radius: 20,
      color: '#90000000',
      offsetX: 0,
      offsetY: 9
    })
    .clip(true)
    .onClick((): void => {
      this.onOpen();
    })
  }
}

@Component
struct SdkFeatureCard {
  @Prop categoryLabel: string = '';
  @Prop watermark: string = '';
  @Prop accentColor: string = '#8EF0C8';
  @Prop icon: Resource = $r('app.media.sdk_feature_storage');
  @Prop iconLabel: string = '';
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop tags: string[] = [];
  @Prop highlightedTag: string = '';
  onOpen: () => void = (): void => {};

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width(126)
        .height(126)
        .position({ right: -40, top: -52 })
        .backgroundColor(this.accentColor)
        .borderRadius(63)
        .opacity(0.09)

      Text(this.watermark)
        .position({ right: 16, bottom: -9 })
        .fontSize(45)
        .fontWeight(FontWeight.Bold)
        .fontColor('#08FFFFFF')
        .letterSpacing(-2)

      Column()
        .width(3)
        .height(54)
        .position({ left: 0, top: 47 })
        .backgroundColor(this.accentColor)
        .borderRadius({ topRight: 2, bottomRight: 2 })

      Column() {
        Row() {
          Row({ space: 8 }) {
            Column()
              .width(7)
              .height(7)
              .backgroundColor(this.accentColor)
              .borderRadius(4)
              .shadow({ radius: 7, color: this.accentColor })

            Text(this.categoryLabel)
              .fontSize(9)
              .fontWeight(FontWeight.Bold)
              .fontColor('#A99A8A')
              .letterSpacing(0.8)
          }

          Blank()

          Text('AVAILABLE')
            .height(25)
            .padding({ left: 10, right: 10 })
            .fontSize(8)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.accentColor)
            .letterSpacing(0.7)
            .textAlign(TextAlign.Center)
            .backgroundColor('#0CFFFFFF')
            .borderRadius(13)
            .border({ width: 1, color: '#18FFFFFF' })
        }
        .width('100%')

        Row() {
          Stack({ alignContent: Alignment.Center }) {
            Column()
              .width(48)
              .height(48)
              .linearGradient({
                angle: 135,
                colors: [[this.accentColor, 0.0], ['#101B1712', 1.0]]
              })
              .borderRadius(14)
              .border({ width: 1, color: this.accentColor })
              .opacity(0.28)

            Column({ space: 1 }) {
              Image(this.icon)
                .width(24)
                .height(22)
                .objectFit(ImageFit.Contain)

              Text(this.iconLabel)
                .fontSize(6)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.accentColor)
                .letterSpacing(0.5)
            }
          }
          .width(48)
          .height(48)

          Column() {
            Text(this.title)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor('#F4F7FB')

            Text(this.subtitle)
              .width('100%')
              .margin({ top: 5 })
              .fontSize(10)
              .fontColor('#81786F')
              .maxLines(2)
          }
          .layoutWeight(1)
          .margin({ left: 13 })
          .alignItems(HorizontalAlign.Start)

          Text('进入')
            .width(58)
            .height(34)
            .margin({ left: 10 })
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor('#08110E')
            .textAlign(TextAlign.Center)
            .backgroundColor(this.accentColor)
            .borderRadius(10)
            .shadow({ radius: 10, color: '#30000000', offsetY: 4 })
        }
        .width('100%')
        .margin({ top: 15 })

        Row({ space: 7 }) {
          ForEach(this.tags, (tag: string) => {
            Text(tag)
              .height(24)
              .padding({ left: 9, right: 9 })
              .fontSize(7)
              .fontWeight(FontWeight.Bold)
              .fontColor(tag === this.highlightedTag ?
                this.accentColor : '#A89A8B')
              .textAlign(TextAlign.Center)
              .backgroundColor(tag === this.highlightedTag ?
                '#12FFFFFF' : '#65080C12')
              .borderRadius(8)
              .border({ width: 1, color: '#18FFFFFF' })
          }, (tag: string): string => tag)
        }
        .width('100%')
        .margin({ top: 14 })
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 16, bottom: 16 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .linearGradient({
      angle: 135,
      colors: [['#F01C1813', 0.0], ['#F00D1117', 0.72], ['#F0151210', 1.0]]
    })
    .borderRadius(18)
    .border({ width: 1, color: '#22FFFFFF' })
    .shadow({ radius: 20, color: '#85000000', offsetY: 9 })
    .clip(true)
    .onClick((): void => {
      this.onOpen();
    })
  }
}

@Entry
@Component
struct Index {
  @StorageLink(XLabModelSelection.STORAGE_KEY)
  private selectedRealtimeModel: string = RealtimeModel.X2_0;
  @StorageLink(XLabConfiguration.API_KEY_STORAGE_KEY)
  private realtimeApiKey: string = '';
  private isPickingVideo: boolean = false;
  private isPickingImage: boolean = false;

  private selectRealtimeModel(model: RealtimeModel): void {
    this.selectedRealtimeModel = model;
  }

  private updateRealtimeApiKey(apiKey: string): void {
    this.realtimeApiKey = apiKey;
  }

  private openStoragePlayground(): void {
    void router.pushUrl({ url: 'modules/xlstorage/StoragePage' });
  }

  private async openUIExtensionPlayground(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    await XLabConfiguration.persistApiKey(context, this.realtimeApiKey);

    const sharedData = new systemShare.SharedData({
      utd: 'general.text',
      content: 'XmaxSDK UIExtensionAbility lifecycle test',
      title: 'XmaxSDK UIExtensionAbility'
    });
    const controller = new systemShare.ShareController(sharedData);

    await controller.show(context, {
      selectionMode: systemShare.SelectionMode.SINGLE,
      previewMode: systemShare.SharePreviewMode.DEFAULT
    });
  }

  private presentUIExtensionPlayground(): void {
    void this.openUIExtensionPlayground().catch((error: Error): void => {
      promptAction.showToast({
        message: `打开 UIExtensionAbility 失败：${error.message}`
      });
    });
  }

  private openRealtimePlayground(
    localVideoPath: string = '',
    localImagePath: string = '',
    usesCustomTrajectoryRenderer: boolean = false
  ): void {
    void router.pushUrl({
      url: 'pages/RealtimePlayground',
      params: {
        localVideoPath: localVideoPath,
        localImagePath: localImagePath,
        usesCustomTrajectoryRenderer: usesCustomTrajectoryRenderer
      }
    });
  }

  private async presentLocalVideoPicker(): Promise<void> {
    if (this.isPickingVideo) {
      return;
    }

    this.isPickingVideo = true;
    try {
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.VIDEO_TYPE;
      options.maxSelectNumber = 1;

      const picker = new photoAccessHelper.PhotoViewPicker();
      const result = await picker.select(options);
      const videoPath: string | undefined = result.photoUris[0];
      if (videoPath !== undefined && videoPath.trim().length > 0) {
        this.openRealtimePlayground(videoPath);
      }
    } catch (_error) {
      promptAction.showToast({ message: '读取视频失败，请重试' });
    } finally {
      this.isPickingVideo = false;
    }
  }

  private async presentLocalImagePicker(
    usesCustomTrajectoryRenderer: boolean = false
  ): Promise<void> {
    if (this.isPickingImage) {
      return;
    }

    this.isPickingImage = true;
    try {
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;

      const picker = new photoAccessHelper.PhotoViewPicker();
      const result = await picker.select(options);
      const imagePath: string | undefined = result.photoUris[0];
      if (imagePath !== undefined && imagePath.trim().length > 0) {
        this.openRealtimePlayground(
          '',
          imagePath,
          usesCustomTrajectoryRenderer
        );
      }
    } catch (_error) {
      promptAction.showToast({ message: '读取图片失败，请重试' });
    } finally {
      this.isPickingImage = false;
    }
  }

  private showComingSoon(mode: string): void {
    promptAction.showToast({ message: `${mode}暂未开放` });
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width(260)
        .height(260)
        .position({ right: -135, top: -55 })
        .backgroundColor('#244B7BFF')
        .borderRadius(130)
        .blur(70)

      Column()
        .width(220)
        .height(220)
        .position({ left: -145, top: 330 })
        .backgroundColor('#1F4DF0B5')
        .borderRadius(110)
        .blur(75)

      Scroll() {
        Column() {
          Row() {
            Row({ space: 11 }) {
              Stack() {
                Column()
                  .width(25)
                  .height(25)
                  .linearGradient({
                    angle: 135,
                    colors: [['#8EF0C8', 0.0], ['#6495FF', 1.0]]
                  })
                  .borderRadius(8)
                  .rotate({ angle: 45 })

                Text('X')
                  .fontSize(12)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#07110D')
              }
              .width(32)
              .height(32)

              Column() {
                Text('XMAXSDK')
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#F2F4F7')
                  .letterSpacing(1.8)

                Text('EXAMPLE / HARMONYOS')
                  .margin({ top: 3 })
                  .fontSize(8)
                  .fontColor('#60FFFFFF')
                  .letterSpacing(1)
              }
              .alignItems(HorizontalAlign.Start)
            }

            Blank()

            ConsoleTag({ label: `v${XMAX_SDK_VERSION}` })
          }
          .width('100%')

          Stack({ alignContent: Alignment.TopStart }) {
            Column()
              .width(96)
              .height(96)
              .position({ right: -36, bottom: -42 })
              .backgroundColor('#146895FF')
              .borderRadius(48)
              .blur(28)

            Column() {
              Row({ space: 7 }) {
                Column()
                  .width(22)
                  .height(2)
                  .backgroundColor('#8EF0C8')
                  .borderRadius(1)

                Text('XMAX PLAYGROUND')
                  .fontSize(9)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#8EF0C8')
                  .letterSpacing(1.2)
              }

              Text('实时交互视频模型')
                .width('100%')
                .margin({ top: 18 })
                .fontSize(24)
                .fontWeight(FontWeight.Bold)
                .fontColor('#F5F7FB')
                .letterSpacing(-0.3)

              Text('选择输入源，启动 XmaxSDK 流式生成链路')
                .width('100%')
                .margin({ top: 12 })
                .fontSize(12)
                .fontColor('#91A0B2')
            }
            .width('100%')
            .padding({ left: 20, right: 20, top: 20, bottom: 20 })
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .margin({ top: 34 })
          .backgroundColor('#C8101620')
          .linearGradient({
            angle: 135,
            colors: [['#E0141D28', 0.0], ['#D00C1118', 1.0]]
          })
          .borderRadius(20)
          .border({ width: 1, color: '#20FFFFFF' })
          .clip(true)
          .shadow({ radius: 24, color: '#65000000', offsetY: 10 })

          Row({ space: 8 }) {
            RuntimeMetric({ label: 'RUNTIME', value: 'HarmonyOS' })
            RuntimeMetric({ label: 'MIN API', value: '18+' })
            RuntimeMetric({ label: 'LATEST MODEL', value: 'X2.0' })
          }
          .width('100%')
          .margin({ top: 12 })

          ModelRegistryCard({
            selectedModel: this.selectedRealtimeModel,
            apiKey: this.realtimeApiKey,
            onSelect: (model: RealtimeModel): void => {
              this.selectRealtimeModel(model);
            },
            onApiKeyChange: (apiKey: string): void => {
              this.updateRealtimeApiKey(apiKey);
            }
          })
            .margin({ top: 14 })

          Row() {
            Column() {
              Text('GENERATION PIPELINES')
                .fontSize(10)
                .fontWeight(FontWeight.Bold)
                .fontColor('#C6D0DD')
                .letterSpacing(1.1)

              Text('选择一种内容输入方式')
                .margin({ top: 5 })
                .fontSize(11)
                .fontColor('#667384')
            }
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .margin({ top: 30, bottom: 14 })

          PipelineCard({
            sequence: '01',
            modeId: 'MODE_01 / CAMERA',
            status: 'READY',
            statusColor: '#8EF0C8',
            title: '摄像头实时流',
            subtitle: '实时采集摄像头画面，持续驱动视频生成。',
            capability: 'createLocalCameraStream()',
            isReady: true,
            onOpen: (): void => {
              this.openRealtimePlayground();
            }
          })

          PipelineCard({
            sequence: '02',
            modeId: 'MODE_02 / VIDEO.FILE',
            status: 'READY',
            statusColor: '#78A9FF',
            title: '视频生成管线',
            subtitle: '选择本地视频，将连续画面逐帧送入生成链路。',
            capability: 'createLocalVideoStream()',
            isReady: true,
            onOpen: (): void => {
              void this.presentLocalVideoPicker();
            }
          })
            .margin({ top: 14 })

          PipelineCard({
            sequence: '03',
            modeId: 'MODE_03 / IMAGE.FILE',
            status: 'READY',
            statusColor: '#C9A3FF',
            title: '图片生成管线',
            subtitle: '选择本地图片，让静态画面持续流动起来。',
            capability: 'createLocalImageStream()',
            isReady: true,
            onOpen: (): void => {
              void this.presentLocalImagePicker();
            }
          })
            .margin({ top: 14 })

          Row() {
            Column() {
              Text('SDK FEATURES')
                .fontSize(10)
                .fontWeight(FontWeight.Bold)
                .fontColor('#C6D0DD')
                .letterSpacing(1.1)

              Text('更多能力与接入示例')
                .margin({ top: 5 })
                .fontSize(11)
                .fontColor('#667384')
            }
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .margin({ top: 30, bottom: 14 })

          SdkFeatureCard({
            categoryLabel: 'HARMONYOS / UI EXTENSION',
            watermark: 'EXT',
            accentColor: '#FF2E88',
            icon: $r('app.media.sdk_feature_ui_extension'),
            iconLabel: 'ABILITY',
            title: 'UIExtensionAbility',
            subtitle: '在 UIExtensionAbility 中验证实时生命周期',
            tags: ['SHARE', 'RTC', 'LIFECYCLE'],
            highlightedTag: 'LIFECYCLE',
            onOpen: (): void => {
              this.presentUIExtensionPlayground();
            }
          })

          SdkFeatureCard({
            categoryLabel: 'SDK RENDERING / TRAJECTORY',
            watermark: 'FX',
            accentColor: '#FF8FD8',
            icon: $r('app.media.sdk_feature_trajectory_custom'),
            iconLabel: 'RENDER',
            title: '自定义轨迹渲染',
            subtitle: '使用自定义 Renderer 绘制交互轨迹。',
            tags: ['CANVAS', 'MULTI-TOUCH', 'CUSTOM EFFECT'],
            highlightedTag: 'CUSTOM EFFECT',
            onOpen: (): void => {
              void this.presentLocalImagePicker(true);
            }
          })
            .margin({ top: 14 })

          SdkFeatureCard({
            categoryLabel: 'SDK SERVICE / STORAGE',
            watermark: 'URL',
            accentColor: '#F5B86C',
            icon: $r('app.media.sdk_feature_storage'),
            iconLabel: 'UPLOAD',
            title: '存储服务',
            subtitle: '上传图片或视频，获取可复用的远程地址',
            tags: ['IMAGE', 'VIDEO', 'REMOTE URL'],
            highlightedTag: 'REMOTE URL',
            onOpen: (): void => {
              this.openStoragePlayground();
            }
          })
            .margin({ top: 14 })

          Column() {
            Divider()
              .width(36)
              .color('#18FFFFFF')

            Text('Copyright © 2026 XMAX.AI PTE. LTD. All rights reserved.')
              .margin({ top: 18 })
              .fontSize(9)
              .fontColor('#4FFFFFFF')
              .textAlign(TextAlign.Center)

            Text('sdk@xmax.ai')
              .margin({ top: 7 })
              .fontSize(9)
              .fontColor('#688EF0C8')
              .letterSpacing(0.4)
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .margin({ top: 10, bottom: 32 })
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%')
        .padding({ left: 18, right: 18, top: 20 })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .expandSafeArea(
        [SafeAreaType.SYSTEM],
        [SafeAreaEdge.BOTTOM]
      )
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#080B10')
    .linearGradient({
      angle: 160,
      colors: [['#0C121B', 0.0], ['#070A0F', 0.48], ['#090D13', 1.0]]
    })
    .expandSafeArea(
      [SafeAreaType.SYSTEM],
      [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]
    )
  }
}
