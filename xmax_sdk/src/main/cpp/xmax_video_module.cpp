#include "napi/native_api.h"
#include "native_audio_file_decoder.h"
#include "native_video_file_decoder.h"

namespace {
napi_value Initialize(
    napi_env env,
    napi_value exports) {
  xmax::DefineNativeAudioFileDecoder(env, exports);
  xmax::DefineNativeVideoFileDecoder(env, exports);
  return exports;
}
}  // namespace

static napi_module videoModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Initialize,
    .nm_modname = "xmax_video",
    .nm_priv = nullptr,
    .reserved = {nullptr, nullptr, nullptr, nullptr},
};

extern "C" __attribute__((constructor)) void RegisterXmaxVideoModule() {
  napi_module_register(&videoModule);
}
