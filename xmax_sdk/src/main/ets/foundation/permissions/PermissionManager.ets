import {
  abilityAccessCtrl,
  common,
  Permissions
} from '@kit.AbilityKit';
import {
  XmaxError,
  XmaxErrorCode
} from '../errors/XmaxError';
import { XmaxLogger } from '../logging/XmaxLogger';
import { PermissionManaging } from './PermissionManaging';

const CAMERA_PERMISSION: Permissions = 'ohos.permission.CAMERA';
const MICROPHONE_PERMISSION: Permissions = 'ohos.permission.MICROPHONE';

/** 检查并申请 SDK 使用相机和麦克风所需的平台权限。 */
export class PermissionManager implements PermissionManaging {

  private readonly context: common.UIAbilityContext;

  /**
   * 创建权限 Manager。
   *
   * @param context 用于检查和申请权限的页面上下文。
   */
  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  /**
   * 确保当前应用已获得相机访问权限。
   *
   * @returns 权限确认完成后的 Promise。
   */
  async ensureCameraPermission(): Promise<void> {
    await this.ensurePermission(
      CAMERA_PERMISSION,
      XmaxErrorCode.CAMERA_PERMISSION_DENIED,
      'Camera permission is unavailable or was denied'
    );
  }

  /**
   * 确保当前应用已获得麦克风访问权限。
   *
   * @returns 权限确认完成后的 Promise。
   */
  async ensureMicrophonePermission(): Promise<void> {
    await this.ensurePermission(
      MICROPHONE_PERMISSION,
      XmaxErrorCode.MICROPHONE_PERMISSION_DENIED,
      'Microphone permission is unavailable or was denied'
    );
  }

  /**
   * 检查指定权限，并在未授权时向用户发起申请。
   *
   * @param permission 平台权限名称。
   * @param errorCode 权限不可用时抛出的 SDK 错误码。
   * @param errorMessage 权限不可用时抛出的错误信息。
   * @returns 权限确认完成后的 Promise。
   */
  private async ensurePermission(
    permission: Permissions,
    errorCode: XmaxErrorCode,
    errorMessage: string
  ): Promise<void> {
    const manager = abilityAccessCtrl.createAtManager();

    try {
      const tokenId: number = this.context.applicationInfo.accessTokenId;
      const current = await manager.checkAccessToken(tokenId, permission);

      if (current === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        return;
      }

      const result = await manager.requestPermissionsFromUser(this.context, [permission]);
      const granted: boolean = result.authResults.length > 0 &&
        result.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;

      if (granted) {
        return;
      }
    } catch (error) {
      const reason: string = error instanceof Error ? error.message : String(error);
      XmaxLogger.error(
        `权限申请失败\n└─ 原因：${reason}`,
        'Permission'
      );
    }

    throw new XmaxError(errorCode, errorMessage);
  }
}
