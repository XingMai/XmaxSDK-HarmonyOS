import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import {
  DefaultTrajectoryEffectRenderer,
  TrajectoryEffectRendering,
  VideoContentMode,
  XmaxVideoView
} from '@xmax/sdk';
import { XLabConfiguration } from './config/XLabConfiguration';
import {
  RealtimeCategoryState,
  RealtimeReferenceItemState,
  RealtimeViewState
} from './mvvm/model/RealtimeViewState';
import { RealtimeLoadingView } from './mvvm/view/RealtimeLoadingView';
import { RealtimePromptInputView } from './mvvm/view/RealtimePromptInputView';
import { RealtimeReferenceListView } from './mvvm/view/RealtimeReferenceListView';
import { RealtimeViewModel } from './mvvm/viewmodel/RealtimeViewModel';
import { CustomTrajectoryRenderer } from './rendering/CustomTrajectoryRenderer';
import { ReferenceCategory, ReferenceCategoryInput } from './reference/ReferenceCategory';
import { ReferencePhotoPicker } from './reference/ReferencePhotoPicker';
import { ReferenceUploader } from './reference/ReferenceUploader';

const CAMERA_SWITCH_BLUR_RADIUS: number = 48;
const LOCAL_FILE_VIEW_TOP_INSET: number = 84;

@Component
struct CancelGenerationButton {
  @Prop isEnabled: boolean = false;
  onCancel: () => void = (): void => {};

  build() {
    Button({ type: ButtonType.Normal }) {
      SymbolGlyph($r('sys.symbol.nosign'))
        .fontSize(13)
        .fontColor(['#FFFFFF'])
    }
    .width(36)
    .height(36)
    .padding(0)
    .backgroundColor(Color.Transparent)
    .borderRadius(18)
    .enabled(this.isEnabled)
    .opacity(this.isEnabled ? 1 : 0.32)
    .animation({ duration: 300, curve: Curve.EaseInOut })
    .accessibilityText('停止生成')
    .onClick(this.onCancel)
  }
}

@Component
export struct RealtimePage {
  @Prop localVideoPath: string = '';
  @Prop localImagePath: string = '';
  @Prop usesCustomTrajectoryRenderer: boolean = false;

  // 页面组件
  private readonly viewModel: RealtimeViewModel = new RealtimeViewModel();
  private readonly promptInputController: TextInputController = new TextInputController();

  // 渲染组件
  private readonly defaultTrajectoryRenderer: TrajectoryEffectRendering =
    new DefaultTrajectoryEffectRenderer();
  private readonly customTrajectoryRenderer: TrajectoryEffectRendering =
    new CustomTrajectoryRenderer();

  // 页面状态
  @State private state: RealtimeViewState = this.viewModel.state;
  @State private isCameraSwitchTransitionActive: boolean = false;
  @State private cameraSwitchBlurRadius: number = 0;
  @State private cameraSwitchRotation: number = 0;
  @State private isPickingLocalMedia: boolean = false;
  private isPickingReference: boolean = false;

  private localContentMode(): VideoContentMode {
    return this.hasLocalFile() ?
      VideoContentMode.FIT : VideoContentMode.FILL;
  }

  private remoteVideoContentMode(): VideoContentMode {
    if (this.hasLocalFile()) {
      return VideoContentMode.FIT;
    }
    return VideoContentMode.FILL;
  }

  private trajectoryRenderer(): TrajectoryEffectRendering {
    return this.usesCustomTrajectoryRenderer ?
      this.customTrajectoryRenderer : this.defaultTrajectoryRenderer;
  }

  private visibleCategories(): ReferenceCategory[] {
    if (!this.hasLocalImage()) {
      return this.state.categories;
    }

    return this.state.categories.filter(
      (category: ReferenceCategory): boolean =>
        category.id === 'mox' || category.id === 'free'
    );
  }

  private visibleCategoryStates(): RealtimeCategoryState[] {
    if (!this.hasLocalImage()) {
      return this.state.categoryStates;
    }

    return this.state.categoryStates.filter(
      (categoryState: RealtimeCategoryState): boolean =>
        categoryState.category.id === 'mox' || categoryState.category.id === 'free'
    );
  }

  private dismissKeyboard(): void {
    this.promptInputController.stopEditing();
  }

  private async switchCamera(): Promise<void> {
    if (this.isCameraSwitchTransitionActive) {
      return;
    }

    this.isCameraSwitchTransitionActive = true;
    this.cameraSwitchBlurRadius = 0;
    this.cameraSwitchRotation = 0;

    await this.coverCameraPreview();

    const switchPromise: Promise<void> = this.viewModel.switchCamera();
    await this.animateCameraSwitch();
    await switchPromise;
    await this.finishCameraSwitchTransition();
  }

  private coverCameraPreview(): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      this.getUIContext().animateTo({
        duration: 140,
        curve: Curve.EaseIn,
        onFinish: (): void => {
          resolve();
        }
      }, (): void => {
        this.cameraSwitchBlurRadius = CAMERA_SWITCH_BLUR_RADIUS;
      });
    });
  }

  private animateCameraSwitch(): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      this.getUIContext().animateTo({
        duration: 500,
        curve: Curve.EaseInOut,
        onFinish: (): void => {
          this.cameraSwitchRotation = 0;
          resolve();
        }
      }, (): void => {
        this.cameraSwitchRotation = 180;
      });
    });
  }

  private finishCameraSwitchTransition(): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      this.getUIContext().animateTo({
        duration: 180,
        curve: Curve.EaseOut,
        onFinish: (): void => {
          this.isCameraSwitchTransitionActive = false;
          resolve();
        }
      }, (): void => {
        this.cameraSwitchBlurRadius = 0;
      });
    });
  }

  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (this.hasLocalImage()) {
      this.viewModel.selectCategory('mox');
    }

    this.viewModel.setReferenceUploader(
      new ReferenceUploader(context, XLabConfiguration.currentApiKey())
    );
    this.viewModel.onMessage = (message: string): void => {
      promptAction.showToast({ message: message });
    };
    void this.viewModel.connect(
      context,
      this.localVideoPath,
      this.localImagePath
    );
  }

  aboutToDisappear(): void {
    this.viewModel.onMessage = null;
    void this.viewModel.disconnect();
  }

  private async presentReferencePhotoPicker(categoryId: string): Promise<void> {
    if (this.isPickingReference) {
      return;
    }
    this.isPickingReference = true;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const filePath: string | undefined = await ReferencePhotoPicker.pickImage(context);
      if (filePath !== undefined) {
        this.viewModel.addLocalReference(categoryId, filePath);
      }
    } catch (_error) {
      promptAction.showToast({ message: '读取照片失败，请重试' });
    } finally {
      this.isPickingReference = false;
    }
  }

  private async presentPromptReferencePhotoPicker(): Promise<void> {
    if (this.isPickingReference) {
      return;
    }
    this.isPickingReference = true;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const filePath: string | undefined = await ReferencePhotoPicker.pickImage(context);
      if (filePath !== undefined) {
        this.viewModel.addPromptReference(filePath);
      }
    } catch (_error) {
      promptAction.showToast({ message: '读取照片失败，请重试' });
    } finally {
      this.isPickingReference = false;
    }
  }

  private async presentLocalMediaPicker(): Promise<void> {
    if (this.isPickingLocalMedia) {
      return;
    }

    this.isPickingLocalMedia = true;
    try {
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = this.hasLocalImage() ?
        photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE :
        photoAccessHelper.PhotoViewMIMETypes.VIDEO_TYPE;
      options.maxSelectNumber = 1;

      const picker = new photoAccessHelper.PhotoViewPicker();
      const result = await picker.select(options);
      const filePath: string | undefined = result.photoUris[0];
      if (filePath === undefined || filePath.trim().length === 0) {
        return;
      }

      if (this.hasLocalImage()) {
        await this.viewModel.replaceLocalImage(filePath);
      } else {
        await this.viewModel.replaceLocalVideo(filePath);
      }
    } catch (_error) {
      const mediaName: string = this.hasLocalImage() ? '图片' : '视频';
      promptAction.showToast({ message: `读取${mediaName}失败，请重试` });
    } finally {
      this.isPickingLocalMedia = false;
    }
  }

  build() {
    Column() {
      Stack({ alignContent: Alignment.TopStart }) {
        Stack({ alignContent: Alignment.TopStart }) {
          if (this.state.localVideoTrack !== null) {
            Stack() {
              XmaxVideoView({
                track: this.state.localVideoTrack,
                contentMode: this.localContentMode()
              })
                .width('100%')
                .height('100%')

              if (this.isCameraSwitchTransitionActive) {
                Row()
                  .width('100%')
                  .height('100%')
                  .backgroundColor('#66000000')
                  .opacity(this.cameraSwitchBlurRadius / CAMERA_SWITCH_BLUR_RADIUS)
                  .hitTestBehavior(HitTestMode.None)
              }
            }
            .width('100%')
            .height('100%')
            .blur(this.cameraSwitchBlurRadius)
            .rotate({
              y: 1,
              angle: this.cameraSwitchRotation,
              perspective: 600
            })
          }

          if (this.state.remoteVideoTrack !== null) {
            XmaxVideoView({
              track: this.state.remoteVideoTrack,
              contentMode: this.remoteVideoContentMode(),
              trajectoryRenderer: this.trajectoryRenderer()
            })
              .width('100%')
              .height('100%')
              .visibility(this.state.isRemoteVideoVisible ? Visibility.Visible : Visibility.Hidden)
          }

          if (this.state.isGenerationStarting) {
            RealtimeLoadingView()
              .transition(TransitionEffect.OPACITY.animation({
                duration: 300,
                curve: Curve.EaseInOut
              }))
          }

          if (this.state.errorMessage.length > 0) {
            Row() {
              Text(this.state.errorMessage)
                .fontSize(12)
                .fontColor('#FFFFFFFF')
                .textAlign(TextAlign.Center)
                .backgroundColor('#B3000000')
                .borderRadius(8)
                .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            }
            .width('100%')
            .height('100%')
            .padding({ left: 68, right: 68 })
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .hitTestBehavior(HitTestMode.None)
          }
        }
        .width('100%')
        .height(this.hasLocalFile() ?
          `calc(100% - ${LOCAL_FILE_VIEW_TOP_INSET}vp)` : '100%')
        .margin({ top: this.hasLocalFile() ? LOCAL_FILE_VIEW_TOP_INSET : 0 })

        if (!this.hasLocalFile()) {
          Button({ type: ButtonType.Normal }) {
            Column({ space: 4 }) {
              Image($r('app.media.realtime_camera_rotate'))
                .width(20)
                .height(20)

              Text('翻转')
                .fontSize(10)
                .lineHeight(12)
                .fontWeight(FontWeight.Medium)
                .fontColor('#FFFFFF')
                .textShadow({ radius: 2, color: '#80000000', offsetX: 0, offsetY: 1 })
            }
            .height(36)
            .justifyContent(FlexAlign.Center)
          }
          .width(58)
          .height(58)
          .padding(0)
          .position({ right: 8, top: 18 })
          .fontColor('#FFFFFF')
          .backgroundColor(Color.Transparent)
          .enabled(!this.isCameraSwitchTransitionActive)
          .accessibilityText('翻转摄像头')
          .onClick((): void => {
            void this.switchCamera();
          })
        } else {
          Button({ type: ButtonType.Normal }) {
            Column({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.picture'))
                .fontSize(20)
                .fontColor(['#FFFFFF'])

              Text('相册')
                .fontSize(10)
                .lineHeight(12)
                .fontWeight(FontWeight.Medium)
                .fontColor('#FFFFFF')
                .textShadow({ radius: 2, color: '#80000000', offsetX: 0, offsetY: 1 })
            }
            .height(36)
            .justifyContent(FlexAlign.Center)
          }
          .width(58)
          .height(58)
          .padding(0)
          .position({ right: 8, top: 18 })
          .fontColor('#FFFFFF')
          .backgroundColor(Color.Transparent)
          .enabled(!this.isPickingLocalMedia)
          .opacity(this.isPickingLocalMedia ? 0.5 : 1)
          .accessibilityText('从相册替换本地素材')
          .onClick((): void => {
            void this.presentLocalMediaPicker();
          })
        }
      }
      .width('100%')
      .layoutWeight(1)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
      .onClick((): void => {
        this.dismissKeyboard();
      })

      Column() {
        Row() {
          CancelGenerationButton({
            isEnabled: this.state.canCancelGeneration,
            onCancel: (): void => {
              this.dismissKeyboard();
              this.viewModel.cancelGeneration();
            }
          })
            .margin({ left: 6, right: 6 })

          List({ space: 22 }) {
            ForEach(this.visibleCategories(), (category: ReferenceCategory) => {
              ListItem() {
                Text(category.name)
                  .height(36)
                  .fontSize(12)
                  .fontWeight(this.state.selectedCategoryId === category.id ?
                    FontWeight.Bold : FontWeight.Regular)
                  .fontColor(this.state.selectedCategoryId === category.id ?
                    '#FFFFFF' : '#7AFFFFFF')
                  .textAlign(TextAlign.Center)
                  .onClick((): void => {
                    this.dismissKeyboard();
                    this.viewModel.selectCategory(category.id);
                  })
              }
            }, (category: ReferenceCategory): string => category.id)
          }
          .listDirection(Axis.Horizontal)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .contentEndOffset(16)
          .layoutWeight(1)
          .height(36)
        }
        .width('100%')
        .height(40)
        .alignItems(VerticalAlign.Bottom)
        .onClick((): void => {
          this.dismissKeyboard();
        })

        Stack({ alignContent: Alignment.TopStart }) {
          ForEach(this.visibleCategoryStates(), (categoryState: RealtimeCategoryState) => {
            if (categoryState.category.input === ReferenceCategoryInput.PROMPT) {
              RealtimePromptInputView({
                prompt: this.state.promptText,
                referenceImageUrl: this.state.promptReferenceImageUrl,
                isReferenceUploading: this.state.isPromptReferenceUploading,
                controller: this.promptInputController,
                onPromptChange: (prompt: string): void => {
                  this.viewModel.updatePromptText(prompt);
                },
                onSubmit: (prompt: string): void => {
                  this.dismissKeyboard();
                  this.viewModel.submitPrompt(prompt);
                },
                onAddReference: (): void => {
                  this.dismissKeyboard();
                  void this.presentPromptReferencePhotoPicker();
                },
                onRemoveReference: (): void => {
                  this.viewModel.removePromptReference();
                }
              })
                .width('calc(100% - 28vp)')
                .margin({ left: 14, right: 14, top: 2 })
                .visibility(this.state.selectedCategoryId === categoryState.category.id ?
                  Visibility.Visible : Visibility.Hidden)
                .hitTestBehavior(this.state.selectedCategoryId === categoryState.category.id ?
                  HitTestMode.Default : HitTestMode.None)
            } else if (categoryState.category.input === ReferenceCategoryInput.INSTRUCTION) {
              Button(this.state.isMoxGenerationActive ?
                categoryState.category.instruction : '点击开始生成', { type: ButtonType.Normal })
                .width('calc(100% - 28vp)')
                .height(40)
                .margin({ left: 14, right: 14, top: 10 })
                .padding({ left: 14, right: 14 })
                .fontSize(this.state.isMoxGenerationActive ? 11 : 12)
                .fontColor(this.state.isMoxGenerationActive ? '#66FFFFFF' : '#D9FFFFFF')
                .backgroundColor(this.state.isMoxGenerationActive ? '#18FFFFFF' : '#24FFFFFF')
                .border({ width: 1, color: '#30FFFFFF' })
                .borderRadius(20)
                .onClick((): void => {
                  this.dismissKeyboard();
                  if (!this.state.isMoxGenerationActive) {
                    this.viewModel.startMoxGeneration();
                  }
                })
                .visibility(this.state.selectedCategoryId === categoryState.category.id ?
                  Visibility.Visible : Visibility.Hidden)
                .hitTestBehavior(this.state.selectedCategoryId === categoryState.category.id ?
                  HitTestMode.Default : HitTestMode.None)
            } else {
              RealtimeReferenceListView({
                listState: categoryState.referenceList,
                onSelectReference: (item: RealtimeReferenceItemState): void => {
                  this.dismissKeyboard();
                  this.viewModel.selectReference(item);
                },
                onAddReference: (categoryId: string): void => {
                  this.dismissKeyboard();
                  void this.presentReferencePhotoPicker(categoryId);
                }
              })
                .visibility(this.state.selectedCategoryId === categoryState.category.id ?
                  Visibility.Visible : Visibility.Hidden)
                .hitTestBehavior(this.state.selectedCategoryId === categoryState.category.id ?
                  HitTestMode.Default : HitTestMode.None)
            }
          }, (categoryState: RealtimeCategoryState): string => categoryState.category.id)
        }
        .width('100%')
        .height(60)
      }
      .width('100%')
      .padding({ bottom: 12 })
      .backgroundColor('#0D0D0E')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
    .expandSafeArea(
      [SafeAreaType.SYSTEM],
      [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]
    )
  }

  private hasLocalFile(): boolean {
    return this.localVideoPath.length > 0 || this.localImagePath.length > 0;
  }

  private hasLocalImage(): boolean {
    return this.localImagePath.length > 0;
  }
}
