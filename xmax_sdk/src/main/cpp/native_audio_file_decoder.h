#ifndef XMAX_NATIVE_AUDIO_FILE_DECODER_H
#define XMAX_NATIVE_AUDIO_FILE_DECODER_H

#include "napi/native_api.h"

namespace xmax {
void DefineNativeAudioFileDecoder(
    napi_env env,
    napi_value exports);
}  // namespace xmax

#endif
