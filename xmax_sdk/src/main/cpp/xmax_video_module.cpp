//
//  xmax_video_module.cpp
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

#include "napi/native_api.h"
#include "native_audio_file_decoder.h"
#include "native_frame_receiver.h"
#include "native_video_file_decoder.h"

namespace {
/**
 * 初始化 SDK 原生模块并挂载媒体创建入口。
 *
 * @param env 当前 ArkTS N-API 执行环境。
 * @param exports 需要挂载 SDK 原生入口的模块导出对象。
 * @returns 已挂载 SDK 原生入口的模块导出对象。
 */
napi_value Initialize(
    napi_env env,
    napi_value exports) {
  xmax::DefineNativeAudioFileDecoder(env, exports);
  xmax::DefineNativeFrameReceiver(env, exports);
  xmax::DefineNativeVideoFileDecoder(env, exports);
  return exports;
}
}  /** namespace */

static napi_module videoModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Initialize,
    .nm_modname = "xmax_video",
    .nm_priv = nullptr,
    .reserved = {nullptr, nullptr, nullptr, nullptr},
};

extern "C" /**
 * 向 N-API 注册 SDK 原生视频模块。
 *
 * @returns 无返回值。
 */
           __attribute__((constructor)) void RegisterXmaxVideoModule() {
  napi_module_register(&videoModule);
}
