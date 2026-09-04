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
      RealtimeModel.X2_PLATFORM_TESTING,
      'X2 Platform Testing',
      'RealtimeModel.X2_PLATFORM_TESTING'
    )
  ];

  static initialize(): void {
    PersistentStorage.persistProp<string>(
      XLabModelSelection.STORAGE_KEY,
      XLabModelSelection.DEFAULT_MODEL
    );
  }

  static current(): RealtimeModel {
    const selectedModel: string | undefined = AppStorage.get<string>(
      XLabModelSelection.STORAGE_KEY
    );
    if (selectedModel === RealtimeModel.X2_PLATFORM_TESTING) {
      return RealtimeModel.X2_PLATFORM_TESTING;
    }
    return XLabModelSelection.DEFAULT_MODEL;
  }
}
