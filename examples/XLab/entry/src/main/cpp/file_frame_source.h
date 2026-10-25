#ifndef XLAB_FILE_FRAME_SOURCE_H
#define XLAB_FILE_FRAME_SOURCE_H

#include "napi/native_api.h"

/** Registers app-owned file decoding, independent of XmaxSDK's capture implementation. */
void DefineFileFrameSource(napi_env env, napi_value exports);

#endif
