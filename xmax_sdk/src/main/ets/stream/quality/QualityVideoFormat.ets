import { ImageSize } from '../../service/media/ImageSize';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';

/** 仅改变传输规格；采集、生成画布和交互坐标基准不随调档改变。 */
export class QualityVideoFormat {
  private static readonly scales: number[] = [1, 0.8, 0.65, 0.5, 0.5];
  private static readonly frameRates: number[] = [30, 24, 24, 20, 16];

  static same(first: RealtimeVideoFormat, second: RealtimeVideoFormat): boolean {
    return first.width === second.width && first.height === second.height && first.fps === second.fps &&
      first.minimumBitrate === second.minimumBitrate && first.maximumBitrate === second.maximumBitrate &&
      first.encoderPreference === second.encoderPreference;
  }

  static resolveDownlinkMaximumSize(baseline: RealtimeVideoFormat, level: number): ImageSize {
    baseline.validate();
    const scale: number = QualityVideoFormat.sizeScale(baseline, level);
    return new ImageSize(baseline.width * scale, baseline.height * scale);
  }

  static resolve(baseline: RealtimeVideoFormat, level: number, downlink: boolean): RealtimeVideoFormat {
    baseline.validate();
    const index: number = QualityVideoFormat.index(level);
    const scale: number = QualityVideoFormat.sizeScale(baseline, level);
    const size: ImageSize = QualityVideoFormat.scaledSize(new ImageSize(baseline.width, baseline.height), scale);
    return new RealtimeVideoFormat(size.width, size.height,
      downlink ? 24 : Math.min(baseline.fps, QualityVideoFormat.frameRates[index]),
      downlink ? undefined : baseline.minimumBitrate, downlink ? undefined : baseline.maximumBitrate,
      baseline.encoderPreference);
  }

  private static index(level: number): number {
    return Math.min(5, Math.max(1, Math.round(level))) - 1;
  }

  private static sizeScale(baseline: RealtimeVideoFormat, level: number): number {
    const shortSide: number = Math.min(baseline.width, baseline.height);
    return Math.max(QualityVideoFormat.scales[QualityVideoFormat.index(level)], Math.min(shortSide, 240) / shortSide);
  }

  private static scaledSize(size: ImageSize, scale: number): ImageSize {
    let divisor: number = size.width;
    let remainder: number = size.height;
    while (remainder !== 0) {
      const next: number = divisor % remainder;
      divisor = remainder;
      remainder = next;
    }
    const units: number = Math.floor(Math.floor(divisor * scale + 0.0000001) / 2) * 2;
    if (units >= 2) {
      return new ImageSize(size.width / divisor * units, size.height / divisor * units);
    }
    return new ImageSize(Math.max(2, Math.floor(size.width * scale / 2) * 2),
      Math.max(2, Math.floor(size.height * scale / 2) * 2));
  }
}
