//
//  native_frame_receiver.h
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

#ifndef XMAX_NATIVE_FRAME_RECEIVER_H
#define XMAX_NATIVE_FRAME_RECEIVER_H

#include "napi/native_api.h"

namespace xmax {
/**
 * 向原生模块导出摄像头帧接收器的创建入口。
 *
 * @param env 当前 ArkTS N-API 执行环境。
 * @param exports 需要挂载 SDK 原生入口的模块导出对象。
 * @returns 无返回值。
 */
void DefineNativeFrameReceiver(
    napi_env env,
    napi_value exports);
}  /** namespace xmax */

#endif
