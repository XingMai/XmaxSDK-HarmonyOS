/** 实时生成启动期间显示的加载遮罩。 */
@Component
export struct RealtimeLoadingView {
  build() {
    Stack({ alignContent: Alignment.Center }) {
      Image($r('app.media.xl_white_loading'))
        .width(54)
        .height(50)
        .objectFit(ImageFit.Contain)
        .accessibilityText('正在开始生成')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#B8000000')
    .hitTestBehavior(HitTestMode.None)
  }
}
