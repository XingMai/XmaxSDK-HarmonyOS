import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import { RtcProviding } from '../../foundation/rtc/RtcProviding';
import {
  RtcQualityLevel,
  RtcQualityListener
} from '../../foundation/rtc/RtcQualityListener';
import {
  RealtimeNetworkQuality,
  RealtimeNetworkQualityLevel,
  RealtimeNetworkQualityListener
} from '../../service/realtime/RealtimeNetworkQuality';
import {
  RealtimePerformanceAlarm,
  RealtimePerformanceAlarmListener,
  RealtimePerformanceStatus
} from '../../service/realtime/RealtimePerformanceAlarm';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import { QualityControlling } from './QualityControlling';

/** 转换 RTC 质量事件并通知实时生成业务监听器。 */
export class QualityController implements QualityControlling, RtcQualityListener {

  // 事件监听
  private networkQualityListener: RealtimeNetworkQualityListener | null = null;
  private performanceAlarmListener: RealtimePerformanceAlarmListener | null = null;

  /**
   * 创建质量监控 Controller。
   *
   * @param rtcProvider 提供质量事件的 RTC Provider。
   */
  constructor(rtcProvider: RtcProviding) {
    rtcProvider.setQualityListener(this);
  }

  /**
   * 设置网络质量监听器。
   *
   * @param listener 网络质量监听器；传入空值时清除监听器。
   * @returns 无返回值。
   */
  setNetworkQualityListener(listener: RealtimeNetworkQualityListener | null): void {
    this.networkQualityListener = listener;
  }

  /**
   * 设置设备性能告警监听器。
   *
   * @param listener 性能告警监听器；传入空值时清除监听器。
   * @returns 无返回值。
   */
  setPerformanceAlarmListener(listener: RealtimePerformanceAlarmListener | null): void {
    this.performanceAlarmListener = listener;
  }

  /**
   * 接收并转换 RTC 上下行网络质量事件。
   *
   * @param uplink 本地上行网络质量。
   * @param downlink 本地下行网络质量。
   * @returns 无返回值。
   */
  onNetworkQuality(
    uplink: RtcQualityLevel,
    downlink: RtcQualityLevel
  ): void {
    const listener: RealtimeNetworkQualityListener | null =
      this.networkQualityListener;
    if (listener === null) {
      return;
    }

    const quality: RealtimeNetworkQuality = new RealtimeNetworkQuality(
      QualityController.networkQualityLevel(uplink),
      QualityController.networkQualityLevel(downlink)
    );

    try {
      listener(quality);
    } catch (error) {
      const reason: string = error instanceof Error ? error.message : String(error);
      XmaxLogger.error(
        `网络质量监听器执行失败\n└─ 原因：${reason}`,
        'Realtime'
      );
    }
  }

  /**
   * 接收 RTC 性能告警并转换建议的视频格式。
   *
   * @param limited 当前设备性能是否受限。
   * @param suggestedWidth 建议的视频宽度。
   * @param suggestedHeight 建议的视频高度。
   * @param suggestedFrameRate 建议的视频帧率。
   * @returns 无返回值。
   */
  onPerformanceAlarm(
    limited: boolean,
    suggestedWidth: number,
    suggestedHeight: number,
    suggestedFrameRate: number
  ): void {
    const listener: RealtimePerformanceAlarmListener | null =
      this.performanceAlarmListener;
    if (listener === null) {
      return;
    }

    const status: RealtimePerformanceStatus = limited ?
      RealtimePerformanceStatus.LIMITED : RealtimePerformanceStatus.RECOVERED;
    const alarm: RealtimePerformanceAlarm = new RealtimePerformanceAlarm(
      status,
      QualityController.suggestedVideoFormat(
        suggestedWidth,
        suggestedHeight,
        suggestedFrameRate
      )
    );

    try {
      listener(alarm);
    } catch (error) {
      const reason: string = error instanceof Error ? error.message : String(error);
      XmaxLogger.error(
        `性能告警监听器执行失败\n└─ 原因：${reason}`,
        'Realtime'
      );
    }
  }

  /**
   * 将 RTC 网络质量等级转换为服务层公开等级。
   *
   * @param level RTC 网络质量等级。
   * @returns 对应的实时生成网络质量等级。
   */
  private static networkQualityLevel(
    level: RtcQualityLevel
  ): RealtimeNetworkQualityLevel {
    switch (level) {
      case RtcQualityLevel.EXCELLENT:
        return RealtimeNetworkQualityLevel.EXCELLENT;
      case RtcQualityLevel.GOOD:
        return RealtimeNetworkQualityLevel.GOOD;
      case RtcQualityLevel.POOR:
        return RealtimeNetworkQualityLevel.POOR;
      case RtcQualityLevel.BAD:
        return RealtimeNetworkQualityLevel.BAD;
      case RtcQualityLevel.VERY_BAD:
        return RealtimeNetworkQualityLevel.VERY_BAD;
      case RtcQualityLevel.DOWN:
        return RealtimeNetworkQualityLevel.DOWN;
      default:
        return RealtimeNetworkQualityLevel.UNKNOWN;
    }
  }

  /**
   * 根据 RTC 建议参数创建可用的视频格式。
   *
   * @param width 建议的视频宽度。
   * @param height 建议的视频高度。
   * @param frameRate 建议的视频帧率。
   * @returns 参数有效时返回视频格式，否则返回空值。
   */
  private static suggestedVideoFormat(
    width: number,
    height: number,
    frameRate: number
  ): RealtimeVideoFormat | undefined {
    if (!QualityController.isPositiveNumber(width) ||
      !QualityController.isPositiveNumber(height) ||
      !QualityController.isPositiveNumber(frameRate)) {
      return undefined;
    }

    return new RealtimeVideoFormat(width, height, frameRate);
  }

  /**
   * 判断数值是否为有限正数。
   *
   * @param value 待检查数值。
   * @returns 数值为有限正数时返回 true，否则返回 false。
   */
  private static isPositiveNumber(value: number): boolean {
    return typeof value === 'number' && Number.isFinite(value) && value > 0;
  }
}
