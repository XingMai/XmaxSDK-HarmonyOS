//
//  QualityVideoFormat.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { ImageSize } from '../../service/media/ImageSize';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';

/** 仅改变传输规格；采集、生成画布和交互坐标基准不随调档改变。 */
export class QualityVideoFormat {

  /** 各档位尺寸比例与帧率上限 */
  private static readonly scales: number[] = [1, 0.8, 0.65, 0.5, 0.5];
  private static readonly frameRates: number[] = [30, 24, 24, 20, 16];

  /**
   * 比较两个传输格式的尺寸、帧率、码率范围和编码偏好。
   *
   * @param first 参与比较的第一个视频格式。
   * @param second 参与比较的第二个视频格式。
   * @returns 所有编码配置均相同时返回 true。
   */
  static same(first: RealtimeVideoFormat, second: RealtimeVideoFormat): boolean {
    return first.width === second.width && first.height === second.height && first.fps === second.fps &&
      first.minimumBitrate === second.minimumBitrate && first.maximumBitrate === second.maximumBitrate &&
      first.encoderPreference === second.encoderPreference;
  }

  /**
   * 按下行档位计算尺寸上限，保护短边且避免放大媒体。
   *
   * @param baseline 保持原始媒体比例与用户编码选项的视频格式基准。
   * @param level 传输档位，范围 1～5，数值越小质量越高。
   * @returns 用于结果流目标尺寸计算的宽高上限。
   */
  static resolveDownlinkMaximumSize(baseline: RealtimeVideoFormat, level: number): ImageSize {
    baseline.validate();
    const scale: number = QualityVideoFormat.sizeScale(baseline, level);
    return new ImageSize(baseline.width * scale, baseline.height * scale);
  }

  /**
   * 按档位计算传输尺寸与帧率，保留上行显式编码选项。
   *
   * @param baseline 保持原始媒体比例与用户编码选项的视频格式基准。
   * @param level 传输档位，范围 1～5，数值越小质量越高。
   * @param downlink 是否为下行方向；false 表示上行。
   * @returns 该传输方向与档位对应的视频格式。
   */
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

  /**
   * 将档位限制在 1～5 并转换为数组索引。
   *
   * @param level 传输档位，范围 1～5，数值越小质量越高。
   * @returns 0～4 的档位索引。
   */
  private static index(level: number): number {
    return Math.min(5, Math.max(1, Math.round(level))) - 1;
  }

  /**
   * 计算档位缩放比例，保护短边至少为原始短边与 240 像素中的较小值。
   *
   * @param baseline 保持原始媒体比例与用户编码选项的视频格式基准。
   * @param level 传输档位，范围 1～5，数值越小质量越高。
   * @returns 不大于 1 的尺寸缩放比例。
   */
  private static sizeScale(baseline: RealtimeVideoFormat, level: number): number {
    const shortSide: number = Math.min(baseline.width, baseline.height);
    return Math.max(QualityVideoFormat.scales[QualityVideoFormat.index(level)], Math.min(shortSide, 240) / shortSide);
  }

  /**
   * 按档位比例缩小媒体，优先保持精确宽高比并输出偶数尺寸。
   *
   * @param size 需要计算或发送的画面尺寸。
   * @param scale 应用到媒体宽高的缩放比例。
   * @returns 可供视频编码使用的偶数宽高。
   */
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
