import { XLabLocalization } from '../../../../localization/XLabLocalization';
/** 本地预览或实时生成准备期间显示的加载遮罩。 */
@Component
export struct RealtimeLoadingView {
  @StorageLink(XLabLocalization.REVISION_KEY) private languageRevision: number = 0;

  private text(key: string): string {
    return XLabLocalization.text(key, this.languageRevision);
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Image($r('app.media.xl_white_loading'))
        .width(54)
        .height(50)
        .objectFit(ImageFit.Contain)
        .accessibilityText(this.text('loading'))
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#B8000000')
    .hitTestBehavior(HitTestMode.None)
  }
}
