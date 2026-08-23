export class XLabConfiguration {
  static readonly API_KEY_STORAGE_KEY: string = 'xlab.realtime.apiKey';

  static initialize(): void {
    PersistentStorage.persistProp<string>(
      XLabConfiguration.API_KEY_STORAGE_KEY,
      ''
    );
  }

  static currentApiKey(): string {
    const apiKey: string | undefined = AppStorage.get<string>(
      XLabConfiguration.API_KEY_STORAGE_KEY
    );
    return apiKey?.trim() ?? '';
  }
}
