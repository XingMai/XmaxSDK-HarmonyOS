import {
  AbilityConstant,
  ShareExtensionAbility,
  UIExtensionContentSession,
  Want
} from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { XLabApplicationLifecycle } from '../application/XLabApplicationLifecycle';
import { XLabConfiguration } from '../modules/xlrealtime/config/XLabConfiguration';
import { XLabModelSelection } from '../modules/xlrealtime/config/XLabModelSelection';

const DOMAIN: number = 0x0000;
const TAG: string = 'XLabShareExtension';

export default class XLabShareExtensionAbility extends ShareExtensionAbility {
  onCreate(_launchParam: AbilityConstant.LaunchParam): void {
    XLabApplicationLifecycle.initialize();
    XLabConfiguration.initialize();
    XLabModelSelection.initialize();
    hilog.info(DOMAIN, TAG, 'UI extension created');
  }

  onForeground(): void {
    XLabApplicationLifecycle.setForeground(true);
  }

  onBackground(): void {
    XLabApplicationLifecycle.setForeground(false);
  }

  onSessionCreate(_want: Want, session: UIExtensionContentSession): void {
    hilog.info(DOMAIN, TAG, 'UI extension session created');
    void this.loadRealtimeContent(session);
  }

  onSessionDestroy(_session: UIExtensionContentSession): void {
    hilog.info(DOMAIN, TAG, 'UI extension session destroyed');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'UI extension destroyed');
  }

  private async loadRealtimeContent(session: UIExtensionContentSession): Promise<void> {
    try {
      await XLabConfiguration.restoreApiKey(this.context);
    } catch (error) {
      const message: string = error instanceof Error ? error.message : String(error);
      hilog.error(DOMAIN, TAG, `Failed to restore API key: ${message}`);
    }
    session.loadContent('pages/UIExtensionRealtimeContent');
  }
}
