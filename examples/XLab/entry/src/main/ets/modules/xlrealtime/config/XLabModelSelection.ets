import { RealtimeModel } from '@xmax/sdk';

export class XLabModelOption {
  readonly model: RealtimeModel;
  readonly title: string;
  readonly symbol: string;

  constructor(model: RealtimeModel, title: string, symbol: string) {
    this.model = model;
    this.title = title;
    this.symbol = symbol;
  }
}

export class XLabModelSelection {
  static readonly STORAGE_KEY: string = 'xlab.realtime.selectedModel';
  static readonly DEFAULT_MODEL: RealtimeModel = RealtimeModel.X2_0;
  static readonly OPTIONS: XLabModelOption[] = [
    new XLabModelOption(
      RealtimeModel.X2_0,
      'X2.0',
      'RealtimeModel.X2_0'
    ),
    new XLabModelOption(
      RealtimeModel.X2_0_PRO,
      'X2.0-PRO',
      'RealtimeModel.X2_0_PRO'
    )
  ];

  static initialize(): void {
    PersistentStorage.persistProp<string>(
      XLabModelSelection.STORAGE_KEY,
      XLabModelSelection.DEFAULT_MODEL
    );
    if (AppStorage.get<string>(XLabModelSelection.STORAGE_KEY) === 'x2.0-sla') {
      AppStorage.set<string>(XLabModelSelection.STORAGE_KEY, RealtimeModel.X2_0_PRO);
    }
  }

  static current(): RealtimeModel {
    const selectedModel: string | undefined = AppStorage.get<string>(
      XLabModelSelection.STORAGE_KEY
    );
    // 旧版本保存的 SLA 选择迁移到 Pro。
    if (selectedModel === RealtimeModel.X2_0_PRO || selectedModel === 'x2.0-sla') {
      return RealtimeModel.X2_0_PRO;
    }
    return XLabModelSelection.DEFAULT_MODEL;
  }
}
