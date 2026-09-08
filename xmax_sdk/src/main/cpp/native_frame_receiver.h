#ifndef XMAX_NATIVE_FRAME_RECEIVER_H
#define XMAX_NATIVE_FRAME_RECEIVER_H

#include "napi/native_api.h"

namespace xmax {
void DefineNativeFrameReceiver(
    napi_env env,
    napi_value exports);
}  // namespace xmax

#endif
