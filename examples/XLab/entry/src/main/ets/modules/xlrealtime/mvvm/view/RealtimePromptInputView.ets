import { vibrator } from '@kit.SensorServiceKit';

@Component
export struct RealtimePromptInputView {
  @Prop prompt: string = '';
  @Prop referenceImageUrl: string = '';
  @Prop isReferenceUploading: boolean = false;
  controller: TextInputController = new TextInputController();
  onPromptChange: (prompt: string) => void = (_prompt: string): void => {};
  onAddReference: () => void = (): void => {};
  onRemoveReference: () => void = (): void => {};
  onSubmit: (prompt: string) => void = (_prompt: string): void => {};

  private normalizedPrompt(): string {
    return this.prompt.trim();
  }

  private displayReferenceImageUrl(): string {
    if (this.referenceImageUrl.length === 0 ||
      !this.referenceImageUrl.startsWith('/')) {
      return this.referenceImageUrl;
    }
    return `file://${this.referenceImageUrl}`;
  }

  private canSubmit(): boolean {
    return this.normalizedPrompt().length > 0 && !this.isReferenceUploading;
  }

  private submit(): void {
    const prompt: string = this.normalizedPrompt();
    if (prompt.length === 0 || this.isReferenceUploading) {
      return;
    }
    vibrator.startVibration(
      {
        type: 'preset',
        effectId: vibrator.HapticFeedback.EFFECT_SOFT,
        count: 1
      },
      { usage: 'touch' }
    ).catch((_error: Object): void => {});
    this.onSubmit(prompt);
  }

  build() {
    Row() {
      TextInput({
        text: this.prompt,
        placeholder: '输入你想要的效果',
        controller: this.controller
      })
        .fontSize(14)
        .fontColor('#FFFFFF')
        .placeholderColor('#80FFFFFF')
        .placeholderFont({ size: 12 })
        .backgroundColor(Color.Transparent)
        .padding(0)
        .layoutWeight(1)
        .height('100%')
        .enterKeyType(EnterKeyType.Send)
        .onChange((value: string): void => {
          this.onPromptChange(value);
        })
        .onSubmit((): void => {
          this.submit();
        })

      Button({ type: ButtonType.Circle }) {
        if (this.isReferenceUploading) {
          LoadingProgress()
            .width(16)
            .height(16)
            .color('#D9D9D9')
        } else if (this.referenceImageUrl.length > 0) {
          Image(this.displayReferenceImageUrl())
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
        } else {
          Image($r('app.media.realtime_prompt_add'))
            .width(14)
            .height(14)
        }
      }
      .width(32)
      .height(32)
      .padding(0)
      .margin({ left: 10 })
      .backgroundColor(this.referenceImageUrl.length > 0 ? Color.Transparent : '#1FFFFFFF')
      .borderRadius(16)
      .clip(true)
      .enabled(!this.isReferenceUploading)
      .accessibilityText(this.referenceImageUrl.length > 0 ? '删除参考图' : '添加参考图')
      .onClick((): void => {
        if (this.referenceImageUrl.length > 0) {
          this.onRemoveReference();
        } else {
          this.onAddReference();
        }
      })

      Button({ type: ButtonType.Circle }) {
        Image($r('app.media.realtime_prompt_submit'))
          .width(13)
          .height(14)
      }
      .width(32)
      .height(32)
      .padding(0)
      .margin({ left: 8 })
      .backgroundColor('#FF2E88')
      .enabled(this.canSubmit())
      .opacity(this.canSubmit() ? 1 : 0.2)
      .accessibilityText('提交指令')
      .onClick((): void => {
        this.submit();
      })
    }
    .width('100%')
    .height(44)
    .padding({ left: 11, right: 8 })
    .backgroundColor('#272728')
    .borderRadius(8)
  }
}
