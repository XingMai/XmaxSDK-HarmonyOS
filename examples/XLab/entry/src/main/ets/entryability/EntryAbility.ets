import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { XLabConfiguration } from '../modules/xlrealtime/config/XLabConfiguration';
import { XLabModelSelection } from '../modules/xlrealtime/config/XLabModelSelection';

const DOMAIN: number = 0x0000;
const TAG: string = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  onCreate(_want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'XLab created');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.getMainWindow()
      .then((mainWindow: window.Window): Promise<void> => {
        mainWindow.setWindowBackgroundColor('#0D0D0E');
        return mainWindow.setWindowLayoutFullScreen(true).then((): Promise<void> => {
          return mainWindow.setWindowSystemBarProperties({
            statusBarColor: '#242733',
            statusBarContentColor: '#FFFFFF',
            isStatusBarLightIcon: true,
            navigationBarColor: '#0D0D0E',
            navigationBarContentColor: '#FFFFFF',
            isNavigationBarLightIcon: true
          });
        });
      })
      .catch((error: Object): void => {
        hilog.warn(DOMAIN, TAG, 'Failed to style system bars: %{public}s', JSON.stringify(error));
      });

    windowStage.loadContent('pages/Index', (error) => {
      if (error.code) {
        hilog.error(
          DOMAIN,
          TAG,
          'Failed to load the XLab page: %{public}s',
          JSON.stringify(error)
        );
        return;
      }

      XLabConfiguration.initialize();
      XLabModelSelection.initialize();
    });
  }
}
