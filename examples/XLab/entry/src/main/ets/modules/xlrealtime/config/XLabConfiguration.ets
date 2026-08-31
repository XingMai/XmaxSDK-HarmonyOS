import { common } from '@kit.AbilityKit';
import { distributedKVStore } from '@kit.ArkData';

export class XLabConfiguration {
  static readonly API_KEY_STORAGE_KEY: string = 'xlab.realtime.apiKey';
  private static readonly KV_STORE_ID: string = 'xlab_configuration';
  private static readonly KV_STORE_API_KEY: string = 'api_key';
  private static kvManager: distributedKVStore.KVManager | null = null;
  private static kvStore: distributedKVStore.SingleKVStore | null = null;

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

  static async persistApiKey(context: common.Context, apiKey: string): Promise<void> {
    const store = await XLabConfiguration.configurationStore(context);
    await store.put(XLabConfiguration.KV_STORE_API_KEY, apiKey.trim());
  }

  static async restoreApiKey(context: common.Context): Promise<void> {
    const store = await XLabConfiguration.configurationStore(context);
    const apiKey = await store.get(XLabConfiguration.KV_STORE_API_KEY);
    AppStorage.setOrCreate<string>(
      XLabConfiguration.API_KEY_STORAGE_KEY,
      typeof apiKey === 'string' ? apiKey.trim() : ''
    );
  }

  private static async configurationStore(
    context: common.Context
  ): Promise<distributedKVStore.SingleKVStore> {
    if (XLabConfiguration.kvStore !== null) {
      return XLabConfiguration.kvStore;
    }

    XLabConfiguration.kvManager = distributedKVStore.createKVManager({
      bundleName: context.applicationInfo.name,
      context: context
    });
    const options: distributedKVStore.Options = {
      createIfMissing: true,
      encrypt: true,
      backup: false,
      autoSync: false,
      kvStoreType: distributedKVStore.KVStoreType.SINGLE_VERSION,
      securityLevel: distributedKVStore.SecurityLevel.S3
    };
    XLabConfiguration.kvStore = await XLabConfiguration.kvManager.getKVStore<distributedKVStore.SingleKVStore>(
      XLabConfiguration.KV_STORE_ID,
      options
    );
    return XLabConfiguration.kvStore;
  }
}
