/** 定义 SDK 所需平台权限的检查与申请能力。 */
export interface PermissionManaging {

  /**
   * 确保已获得相机访问权限。
   *
   * @returns 权限确认完成后的 Promise。
   */
  ensureCameraPermission(): Promise<void>;

  /**
   * 确保已获得麦克风访问权限。
   *
   * @returns 权限确认完成后的 Promise。
   */
  ensureMicrophonePermission(): Promise<void>;
}
