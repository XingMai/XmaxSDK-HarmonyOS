//
//  PermissionManager.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

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

/** Checks and requests camera and microphone permissions. */
export class PermissionManager implements PermissionManaging {

  /** The platform context for SDK resources. */
  private readonly context: common.UIAbilityContext;

  /** Creates a permission manager. */
  constructor(
    context: common.UIAbilityContext
  ) {
    this.context = context;
  }

  /**
   * Ensures your app has camera access.
   *
   * The Promise fulfills after permission is confirmed.
   */
  async ensureCameraPermission(): Promise<void> {
    await this.ensurePermission(
      CAMERA_PERMISSION,
      XmaxErrorCode.CAMERA_PERMISSION_DENIED,
      'Camera permission is unavailable or was denied'
    );
  }

  /**
   * Ensures your app has microphone access.
   *
   * The Promise fulfills after permission is confirmed.
   */
  async ensureMicrophonePermission(): Promise<void> {
    await this.ensurePermission(
      MICROPHONE_PERMISSION,
      XmaxErrorCode.MICROPHONE_PERMISSION_DENIED,
      'Microphone permission is unavailable or was denied'
    );
  }

  /**
   * Checks a permission and requests it if not granted.
   *
   * The Promise fulfills after permission is confirmed.
   *
   * @param permission The platform permission name.
   * @param errorCode The SDK error code for unavailable permission.
   * @param errorMessage The message for unavailable permission.
   */
  private async ensurePermission(
    permission: Permissions,
    errorCode: XmaxErrorCode,
    errorMessage: string
  ): Promise<void> {
    const manager = abilityAccessCtrl.createAtManager();

    try {
      const tokenId: number = this.context.applicationInfo.accessTokenId;
      const current = await manager.checkAccessToken(
        tokenId,
        permission
      );

      if (current === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        return;
      }

      const result = await manager.requestPermissionsFromUser(
        this.context,
        [permission]
      );
      const granted: boolean = result.authResults.length > 0 &&
        result.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;

      if (granted) {
        return;
      }
    } catch (error) {
      const reason: string = error instanceof Error ? error.message : String(error);
      XmaxLogger.error(
        `${XmaxLogger.localized("权限申请失败 (Permission Request Failed)\n└─ 原因：", "权限申请失败 (Permission Request Failed)\n└─ Reason: ")}${reason}`,
        'Permission'
      );
    }

    throw new XmaxError(
      errorCode,
      errorMessage
    );
  }
}
