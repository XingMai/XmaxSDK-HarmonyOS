export class XLabApplicationLifecycle {

  static readonly FOREGROUND_STORAGE_KEY: string = 'xlab.application.foreground';

  static initialize(): void {
    AppStorage.setOrCreate<boolean>(
      XLabApplicationLifecycle.FOREGROUND_STORAGE_KEY,
      true
    );
  }

  static setForeground(isForeground: boolean): void {
    AppStorage.setOrCreate<boolean>(
      XLabApplicationLifecycle.FOREGROUND_STORAGE_KEY,
      isForeground
    );
  }
}
