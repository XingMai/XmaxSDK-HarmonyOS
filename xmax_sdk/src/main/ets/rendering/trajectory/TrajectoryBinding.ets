//
//  TrajectoryBinding.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { ImageSize } from '../../service/media/ImageSize';
import { VideoContentMode } from '../../foundation/media/video/VideoContentMode';
import { InteractionControlling } from '../../media/interaction/InteractionControlling';
import { InteractionFrame } from '../../media/interaction/InteractionFrame';
import { InteractionPoint } from '../../media/interaction/InteractionPoint';

/** 绑定生成任务的交互发送能力和媒体尺寸，供视图提交触点。 */
export class TrajectoryBinding {

  /** 交互发送依赖 */
  private readonly interactionController: InteractionControlling;

  /** 固定媒体坐标基准 */
  private mediaSize: ImageSize;

  /**
   * 创建视频轨道交互绑定。
   *
   * @param interactionController 将归一化触点发送到当前任务的交互组件。
   * @param resolvedMediaSize 固定的处理后媒体基准；远端轨道或回传分辨率变化不改变此值。
   * @returns 新建的 TrajectoryBinding 实例。
   */
  constructor(interactionController: InteractionControlling, resolvedMediaSize: ImageSize) {
    this.interactionController = interactionController;
    this.mediaSize = resolvedMediaSize;
  }

  /**
   * 固定的处理后媒体基准；远端轨道或回传分辨率变化不改变此值。
   *
   * @returns 计算得到的媒体宽高。
   */
  get resolvedMediaSize(): ImageSize {
    return this.mediaSize;
  }

  /**
   * 仅在本地媒体规格变化（例如相机转屏）时更新。
   *
   * @param size 需要计算或发送的画面尺寸。
   * @returns 无返回值。
   */
  updateResolvedMediaSize(size: ImageSize): void {
    this.mediaSize = size;
  }

  /**
   * 将视口触点转换为有效媒体区域的归一化交互点并发送。
   *
   * @param points 本次提交或绘制的触点集合。
   * @param viewportWidth 交互视口宽度，单位与触点坐标一致。
   * @param viewportHeight 交互视口高度，单位与触点坐标一致。
   * @param contentMode 媒体在视口中的完整显示或裁剪填充方式。
   * @returns 无返回值。
   */
  submit(
    points: InteractionPoint[],
    viewportWidth: number,
    viewportHeight: number,
    contentMode: VideoContentMode
  ): void {
    if (points.length === 0) {
      return;
    }

    this.interactionController.submit(new InteractionFrame(
      points,
      viewportWidth,
      viewportHeight,
      contentMode
    ));
  }
}
