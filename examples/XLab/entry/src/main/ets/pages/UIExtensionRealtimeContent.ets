import { common } from '@kit.AbilityKit';
import { RealtimePage } from '../modules/xlrealtime/RealtimePage';

@Entry
@Component
struct UIExtensionRealtimeContent {
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
      .accessibilityText('关闭 UIExtensionAbility')
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
