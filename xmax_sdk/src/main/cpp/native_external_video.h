//
//  native_external_video.h
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

#ifndef XMAX_NATIVE_EXTERNAL_VIDEO_H
#define XMAX_NATIVE_EXTERNAL_VIDEO_H

#include "napi/native_api.h"

namespace xmax {

/**
 * Exports synchronous owned external-frame conversion.
 *
 * @param env The current ArkTS N-API environment.
 * @param exports The module object receiving the conversion method.
 */
void DefineNativeExternalVideo(napi_env env, napi_value exports);
} // namespace xmax

#endif
