import { Reference, ReferenceUploadState } from '../../reference/Reference';
import { RealtimeReferenceItemState } from '../model/RealtimeViewState';

@Component
export struct RealtimeReferenceCell {
  @ObjectLink item: RealtimeReferenceItemState;
  @ObjectLink reference: Reference;

  private displayImageUrl(): string | undefined {
    const imageUrl: string | undefined = this.reference.imageUrl;
    if (imageUrl === undefined || !imageUrl.startsWith('/')) {
      return imageUrl;
    }
    return `file://${imageUrl}`;
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Stack({ alignContent: Alignment.Center }) {
        if (this.item.reference.isAddAction) {
          Image($r('app.media.realtime_add_reference'))
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
        } else if (this.displayImageUrl() !== undefined) {
          Image(this.displayImageUrl())
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
        }

        if (!this.reference.isAddAction &&
          this.reference.uploadState === ReferenceUploadState.UPLOADING) {
          Stack({ alignContent: Alignment.Center }) {
            LoadingProgress()
              .width(20)
              .height(20)
              .color('#FFFFFF')
          }
          .width('100%')
          .height('100%')
          .backgroundColor('#6B000000')
        } else if (!this.reference.isAddAction &&
          this.reference.uploadState === ReferenceUploadState.FAILED) {
          Stack({ alignContent: Alignment.Center }) {
            SymbolGlyph($r('sys.symbol.arrow_clockwise'))
              .fontSize(18)
              .fontColor(['#FFFFFF'])
          }
          .width('100%')
          .height('100%')
          .backgroundColor('#75000000')
        }
      }
      .width(44)
      .height(44)
      .backgroundColor('#303032')
      .borderRadius(7)
      .clip(true)
    }
    .width(48)
    .height(48)
    .backgroundColor(this.item.isSelected ? '#FF4F9A' : Color.Transparent)
    .borderRadius(9)
  }
}
