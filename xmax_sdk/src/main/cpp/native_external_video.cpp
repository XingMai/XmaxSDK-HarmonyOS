//
//  native_external_video.cpp
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

#include "native_external_video.h"
#include "external_video_converter.h"

#include <cmath>
#include <stdexcept>
#include <string>

namespace xmax {
namespace {

/** Rejects malformed N-API arguments without exposing platform error codes. */
void Require(napi_status status) {
  if (status != napi_ok) throw std::runtime_error("Invalid external frame argument");
}

/** Reads one required property from a frame or plane. */
napi_value Property(napi_env env, napi_value object, const char *name) {
  napi_value value;
  Require(napi_get_named_property(env, object, name, &value));
  return value;
}

/** Reads a nonnegative integral byte offset, dimension, or length. */
int64_t Number(napi_env env, napi_value value) {
  double number = 0;
  Require(napi_get_value_double(env, value, &number));
  if (!std::isfinite(number) || number < 0 || number > INT32_MAX || std::floor(number) != number) {
    throw std::runtime_error("Invalid external frame number");
  }
  return static_cast<int64_t>(number);
}

/** Reads a visible plane while retaining the input frame throughout the synchronous call. */
ExternalVideoPlane Plane(napi_env env, napi_value planes, uint32_t index) {
  napi_value plane;
  Require(napi_get_element(env, planes, index, &plane));
  void *address = nullptr;
  size_t capacity = 0;
  Require(napi_get_arraybuffer_info(env, Property(env, plane, "data"), &address, &capacity));
  const size_t offset = Number(env, Property(env, plane, "byteOffset"));
  const size_t length = Number(env, Property(env, plane, "byteLength"));
  const int32_t stride = Number(env, Property(env, plane, "stride"));
  if (!address || offset > capacity || length > capacity - offset) {
    throw std::runtime_error("Invalid external frame plane range");
  }
  return {static_cast<uint8_t *>(address) + offset, length, stride};
}

/** Processes source pixels before returning, so the app can immediately reuse its buffers. */
napi_value Convert(napi_env env, napi_callback_info info) {
  try {
    size_t count = 3;
    napi_value args[3];
    Require(napi_get_cb_info(env, info, &count, args, nullptr, nullptr));
    if (count != 3) throw std::runtime_error("External video requires a frame and output dimensions");
    const int32_t width = Number(env, Property(env, args[0], "width"));
    const int32_t height = Number(env, Property(env, args[0], "height"));
    const int32_t outputWidth = Number(env, args[1]);
    const int32_t outputHeight = Number(env, args[2]);
    if (Number(env, Property(env, args[0], "rotation")) != 0) {
      throw std::runtime_error("External video must be upright");
    }

    char pixelFormat[16]{};
    size_t length = 0;
    Require(napi_get_value_string_utf8(env, Property(env, args[0], "pixelFormat"),
        pixelFormat, sizeof(pixelFormat), &length));
    if (length >= sizeof(pixelFormat)) throw std::runtime_error("Unsupported external pixel format");
    const std::string format(pixelFormat, length);
    if (format != "nv12" && format != "bgra") throw std::runtime_error("Unsupported external pixel format");
    napi_value planes = Property(env, args[0], "planes");
    uint32_t planeCount = 0;
    Require(napi_get_array_length(env, planes, &planeCount));
    if (planeCount != (format == "bgra" ? 1u : 2u)) throw std::runtime_error("Invalid external plane count");
    const ExternalVideoPlane first = Plane(env, planes, 0);
    const ExternalVideoPlane second = format == "bgra" ? ExternalVideoPlane{nullptr, 0, 0} : Plane(env, planes, 1);

    const int64_t pixels = static_cast<int64_t>(outputWidth) * outputHeight;
    if (pixels <= 0 || pixels > 16777216) throw std::runtime_error("External video output is too large");
    void *destination = nullptr;
    napi_value result;
    Require(napi_create_arraybuffer(env, pixels * 3 / 2, &destination, &result));
    ConvertExternalVideo(first, second, format == "bgra", width, height, outputWidth, outputHeight,
        static_cast<uint8_t *>(destination));
    return result;
  } catch (const std::exception &error) {
    napi_throw_error(env, nullptr, error.what());
    return nullptr;
  }
}
} // namespace

void DefineNativeExternalVideo(napi_env env, napi_value exports) {
  napi_property_descriptor method = {"convertExternalVideoFrame", nullptr, Convert,
      nullptr, nullptr, nullptr, napi_default, nullptr};
  napi_define_properties(env, exports, 1, &method);
}
} // namespace xmax
