import { common } from '@kit.AbilityKit';
import { i18n, resourceManager } from '@kit.LocalizationKit';
import { XmaxEnvironment } from '@xmax/sdk';

export enum XLabLanguage {
  SYSTEM = 'system',
  CHINESE = 'zh-Hans',
  ENGLISH = 'en'
}

/** 界面语言独立于系统设置，中文连接国内服务，英文连接海外服务。 */
export class XLabLocalization {
  static readonly LANGUAGE_KEY: string = 'xlab.language';
  static readonly REVISION_KEY: string = 'xlab.languageRevision';
  private static resources: resourceManager.ResourceManager | null = null;
  private static localizedResources: resourceManager.ResourceManager | null = null;
  private static resourceLanguage: string = '';

  static initialize(context: common.Context): void {
    PersistentStorage.persistProp<string>(XLabLocalization.LANGUAGE_KEY, XLabLanguage.SYSTEM);
    if (AppStorage.get<number>(XLabLocalization.REVISION_KEY) === undefined) {
      AppStorage.setOrCreate<number>(XLabLocalization.REVISION_KEY, 0);
    }
    XLabLocalization.resources = context.resourceManager;
    XLabLocalization.localizedResources = null;
    XLabLocalization.refresh();
  }

  static get language(): XLabLanguage {
    const value = AppStorage.get<string>(XLabLocalization.LANGUAGE_KEY);
    return value === XLabLanguage.CHINESE ? XLabLanguage.CHINESE :
      value === XLabLanguage.ENGLISH ? XLabLanguage.ENGLISH : XLabLanguage.SYSTEM;
  }

  static get languageCode(): string {
    const language = XLabLocalization.language;
    if (language !== XLabLanguage.SYSTEM) {
      return language;
    }
    return i18n.System.getSystemLanguage().toLowerCase().startsWith('zh') ? 'zh-Hans' : 'en';
  }

  static get environment(): XmaxEnvironment {
    return XLabLocalization.languageCode === 'zh-Hans' ? XmaxEnvironment.CHINA : XmaxEnvironment.GLOBAL;
  }

  static setLanguage(language: XLabLanguage): void {
    AppStorage.setOrCreate<string>(XLabLocalization.LANGUAGE_KEY, language);
    XLabLocalization.refresh();
  }

  /** 前台恢复或系统配置改变时刷新已显示的组件，不重建媒体管线。 */
  static refresh(): void {
    const language = XLabLocalization.languageCode;
    if (XLabLocalization.resourceLanguage === language && XLabLocalization.localizedResources !== null) {
      return;
    }
    const resources = XLabLocalization.resources;
    if (resources === null) {
      return;
    }
    const configuration = resources.getConfigurationSync();
    configuration.locale = language;
    XLabLocalization.localizedResources = resources.getOverrideResourceManager(configuration);
    XLabLocalization.resourceLanguage = language;
    AppStorage.setOrCreate<number>(XLabLocalization.REVISION_KEY,
      (AppStorage.get<number>(XLabLocalization.REVISION_KEY) ?? 0) + 1);
  }

  /** revision 让 ArkUI 将文案表达式与语言变更关联。 */
  static text(key: string, _revision: number = 0): string {
    XLabLocalization.refresh();
    return XLabLocalization.localizedResources?.getStringByNameSync(key) ?? key;
  }

  static format(key: string, values: string[], revision: number = 0): string {
    return XLabLocalization.text(key, revision).replace(/\{(\d+)\}/g, (placeholder: string, index: string): string => {
      return values[Number(index)] ?? placeholder;
    });
  }
}
