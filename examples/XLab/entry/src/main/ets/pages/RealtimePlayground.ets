import { XLabLocalization } from '../localization/XLabLocalization';
import { router } from '@kit.ArkUI';
import { RealtimePage } from '../modules/xlrealtime/RealtimePage';

interface RealtimePlaygroundParameters {
  localVideoPath?: string;
  localImagePath?: string;
  usesCustomTrajectoryRenderer?: boolean;
}

@Entry
@Component
struct RealtimePlayground {
  @StorageLink(XLabLocalization.REVISION_KEY) private languageRevision: number = 0;

  private text(key: string): string {
    return XLabLocalization.text(key, this.languageRevision);
  }

  private localVideoPath(): string {
    const parameters = router.getParams() as RealtimePlaygroundParameters;
    return parameters.localVideoPath ?? '';
  }

  private localImagePath(): string {
    const parameters = router.getParams() as RealtimePlaygroundParameters;
    return parameters.localImagePath ?? '';
  }

  private usesCustomTrajectoryRenderer(): boolean {
    const parameters = router.getParams() as RealtimePlaygroundParameters;
    return parameters.usesCustomTrajectoryRenderer ?? false;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      RealtimePage({
        localVideoPath: this.localVideoPath(),
        localImagePath: this.localImagePath(),
        usesCustomTrajectoryRenderer: this.usesCustomTrajectoryRenderer()
      })

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
      .accessibilityText(this.text('back_playground'))
      .onClick((): void => {
        router.back();
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
