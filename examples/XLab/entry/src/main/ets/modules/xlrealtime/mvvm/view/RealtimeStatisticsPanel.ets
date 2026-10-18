import { RealtimeNetworkQualityLevel } from '@xmax/sdk';
import { XLabLocalization } from '../../../../localization/XLabLocalization';
import { RealtimeViewState } from '../model/RealtimeViewState';

@Component
export struct RealtimeStatisticsButton {
  @StorageLink(XLabLocalization.REVISION_KEY) private languageRevision: number = 0;
  @Prop isActive: boolean = false;
  onToggle: () => void = (): void => {};

  private text(key: string): string {
    return XLabLocalization.text(key, this.languageRevision);
  }

  build() {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 4 }) {
        Image($r('app.media.realtime_statistics'))
          .width(20)
          .height(20)
          .fillColor(this.isActive ? '#60A5FA' : '#FFFFFF')
        Text(this.text('stats_title'))
          .fontSize(10)
          .lineHeight(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.isActive ? '#60A5FA' : '#FFFFFF')
      }
      .height(36)
      .justifyContent(FlexAlign.Center)
    }
    .width(58)
    .height(58)
    .padding(0)
    .backgroundColor(Color.Transparent)
    .accessibilityText(this.text('stats_title'))
    .accessibilityDescription(this.text(this.isActive ? 'stats_enabled' : 'stats_disabled'))
    .onClick(this.onToggle)
  }
}

/** 用 @Prop 接收每次统计更新；@Builder 按值参数只保留构建时的快照。 */
@Component
struct RealtimeStatisticsRow {
  @Prop label: string = '';
  @Prop value: string = '—';

  build() {
    Row({ space: 8 }) {
      Text(this.label).fontSize(10).fontColor('#CCFFFFFF').layoutWeight(1)
      Text(this.value).fontSize(10).fontColor('#FFFFFF').textAlign(TextAlign.End)
    }
    .width('100%')
    .height(16)
  }
}

@Component
export struct RealtimeStatisticsPanel {
  @StorageLink(XLabLocalization.REVISION_KEY) private languageRevision: number = 0;
  @ObjectLink state: RealtimeViewState;
  @Prop maximumHeight: string = '100%';

  private text(key: string): string {
    return XLabLocalization.text(key, this.languageRevision);
  }

  private number(value: number | undefined, unit: string = ''): string {
    if (value === undefined || !Number.isFinite(value)) { return '—'; }
    return value.toFixed(2).replace(/\.?0+$/, '') + unit;
  }

  private resolution(width: number | undefined, height: number | undefined): string {
    return width === undefined || height === undefined ? '—' : `${width} × ${height}`;
  }

  private quality(level: RealtimeNetworkQualityLevel | undefined): string {
    switch (level) {
      case RealtimeNetworkQualityLevel.EXCELLENT: return this.text('stats_quality_excellent');
      case RealtimeNetworkQualityLevel.GOOD: return this.text('stats_quality_good');
      case RealtimeNetworkQualityLevel.POOR: return this.text('stats_quality_poor');
      case RealtimeNetworkQualityLevel.BAD: return this.text('stats_quality_bad');
      case RealtimeNetworkQualityLevel.VERY_BAD: return this.text('stats_quality_very_bad');
      case RealtimeNetworkQualityLevel.DOWN: return this.text('stats_quality_down');
      default: return '—';
    }
  }

  build() {
    Scroll() {
      Column({ space: 0 }) {
        Text(this.text('stats_uplink'))
          .fontSize(11).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
          .width('100%').margin({ bottom: 4 })
        RealtimeStatisticsRow({ label: this.text('stats_resolution'), value: this.resolution(
          this.state.uplinkStatistics?.width, this.state.uplinkStatistics?.height) })
        RealtimeStatisticsRow({ label: this.text('stats_capture_fps'), value: this.number(this.state.uplinkStatistics?.captureFrameRate, ' fps') })
        RealtimeStatisticsRow({ label: this.text('stats_encode_fps'), value: this.number(this.state.uplinkStatistics?.encodeFrameRate, ' fps') })
        RealtimeStatisticsRow({ label: this.text('stats_send_fps'), value: this.number(this.state.uplinkStatistics?.sendFrameRate, ' fps') })
        RealtimeStatisticsRow({ label: this.text('stats_bitrate'), value: this.number(this.state.uplinkStatistics?.bitrateKbps, ' kbps') })
        RealtimeStatisticsRow({ label: this.text('stats_loss'), value: this.number(this.state.uplinkStatistics?.packetLossPercent, '%') })
        RealtimeStatisticsRow({ label: this.text('stats_quality'), value: this.quality(this.state.networkQuality?.uplink) })
        Text(this.text('stats_downlink'))
          .fontSize(11).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
          .width('100%').margin({ top: 12, bottom: 4 })
        RealtimeStatisticsRow({ label: this.text('stats_resolution'), value: this.resolution(
          this.state.downlinkStatistics?.width, this.state.downlinkStatistics?.height) })
        RealtimeStatisticsRow({ label: this.text('stats_decode_fps'), value: this.number(this.state.downlinkStatistics?.decodeFrameRate, ' fps') })
        RealtimeStatisticsRow({ label: this.text('stats_render_fps'), value: this.number(this.state.downlinkStatistics?.renderFrameRate, ' fps') })
        RealtimeStatisticsRow({ label: this.text('stats_bitrate'), value: this.number(this.state.downlinkStatistics?.bitrateKbps, ' kbps') })
        RealtimeStatisticsRow({ label: this.text('stats_loss'), value: this.number(this.state.downlinkStatistics?.packetLossPercent, '%') })
        RealtimeStatisticsRow({ label: this.text('stats_quality'), value: this.quality(this.state.networkQuality?.downlink) })
        RealtimeStatisticsRow({ label: this.text('stats_delay'), value: this.number(this.state.downlinkStatistics?.endToEndDelayMs, ' ms') })
      }
      .width('100%')
      .padding(10)
    }
    .constraintSize({ maxHeight: this.maximumHeight })
    .scrollBar(BarState.Off)
    .backgroundColor('#A3000000')
    .borderRadius(8)
  }
}
