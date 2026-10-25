//
//  native_video_file_decoder.h
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

#ifndef XMAX_NATIVE_VIDEO_FILE_DECODER_H
#define XMAX_NATIVE_VIDEO_FILE_DECODER_H

#include "napi/native_api.h"

namespace xmax {

/**
 * Exports asynchronous native video decoder creation.
 *
 * @param env The current ArkTS N-API environment.
 * @param exports The module object receiving SDK native exports.
 */
void DefineNativeVideoFileDecoder(napi_env env, napi_value exports);
} // namespace xmax

#endif
