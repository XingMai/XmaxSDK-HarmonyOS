//
//  xmax_video_module.cpp
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

#include "napi/native_api.h"
#include "native_external_video.h"
#include "native_audio_file_decoder.h"
#include "native_frame_receiver.h"
#include "native_video_file_decoder.h"

namespace {

/**
 * Initializes SDK native media exports.
 *
 * @param env The current ArkTS N-API environment.
 * @param exports The module object receiving SDK native exports.
 * @return The module object with SDK native exports.
 */
napi_value Initialize(napi_env env, napi_value exports) {
  xmax::DefineNativeExternalVideo(env, exports);
  xmax::DefineNativeAudioFileDecoder(env, exports);
  xmax::DefineNativeFrameReceiver(env, exports);
  xmax::DefineNativeVideoFileDecoder(env, exports);
  return exports;
}
} // namespace

static napi_module videoModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Initialize,
    .nm_modname = "xmax_video",
    .nm_priv = nullptr,
    .reserved = {nullptr, nullptr, nullptr, nullptr},
};

extern "C" /** Registers the SDK native video module with N-API. */
    __attribute__((constructor)) void
    RegisterXmaxVideoModule() {
  napi_module_register(&videoModule);
}
