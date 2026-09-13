import { XLabLocalization } from '../localization/XLabLocalization';
import { common } from '@kit.AbilityKit';
import { RealtimePage } from '../modules/xlrealtime/RealtimePage';

@Entry
@Component
struct UIExtensionRealtimeContent {
  @StorageLink(XLabLocalization.REVISION_KEY) private languageRevision: number = 0;

  private text(key: string): string {
    return XLabLocalization.text(key, this.languageRevision);
  }

  private closeExtension(): void {
    const context = this.getUIContext().getHostContext() as common.UIExtensionContext;
    void context.terminateSelf();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      RealtimePage()

      Button({ type: ButtonType.Normal }) {
        Image($r('app.media.realtime_nav_back'))
          .width(36)
          .height(36)
      }
      .width(58)
      .height(58)
      .padding(0)
      .position({ left: 8, top: 18 })
      .backgroundColor(Color.Transparent)
      .accessibilityText(this.text('close_extension'))
      .onClick((): void => {
        this.closeExtension();
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
    .expandSafeArea(
      [SafeAreaType.SYSTEM],
      [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]
    )
  }
}
