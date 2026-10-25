//
//  native_remote_audio.h
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

#ifndef XMAX_NATIVE_REMOTE_AUDIO_H
#define XMAX_NATIVE_REMOTE_AUDIO_H

#include "napi/native_api.h"

namespace xmax {

/** Exports RTC PCM observation with timestamps copied from the native audio frame. */
void DefineNativeRemoteAudio(napi_env env, napi_value exports);

} // namespace xmax

#endif
