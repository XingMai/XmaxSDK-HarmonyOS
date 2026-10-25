//
//  external_video_converter.cpp
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

#include "external_video_converter.h"

#include <stdexcept>
#include <vector>

#include "libyuv/convert_from_argb.h"
#include "libyuv/scale.h"

namespace xmax {
namespace {

/** Rejects unsupported dimensions before multiplication or allocation. */
void ValidateSize(int32_t width, int32_t height) {
  if (width < 2 || height < 2 || width % 2 != 0 || height % 2 != 0 ||
      width > 32768 || height > 32768 || static_cast<int64_t>(width) * height > 16777216) {
    throw std::runtime_error("Invalid external video dimensions");
  }
}

/** Checks the full visible plane, allowing omitted padding after its last row. */
void ValidatePlane(ExternalVideoPlane plane, int32_t rowBytes, int32_t height) {
  if (!plane.data || plane.stride < rowBytes ||
      static_cast<uint64_t>(height - 1) * plane.stride + rowBytes > plane.length) {
    throw std::runtime_error("Invalid external video plane or stride");
  }
}
} // namespace

void ConvertExternalVideo(ExternalVideoPlane first, ExternalVideoPlane second, bool bgra,
    int32_t width, int32_t height, int32_t outputWidth, int32_t outputHeight, uint8_t *output) {
  ValidateSize(width, height);
  ValidateSize(outputWidth, outputHeight);
  ValidatePlane(first, bgra ? width * 4 : width, height);
  if (!output) throw std::runtime_error("Missing external video output");

  std::vector<uint8_t> converted;
  if (bgra) {
    // libyuv ARGB is stored in little-endian memory as B, G, R, A.
    const size_t ySize = static_cast<size_t>(width) * height;
    converted.resize(ySize * 3 / 2);
    if (libyuv::ARGBToNV12(first.data, first.stride, converted.data(), width,
        converted.data() + ySize, width, width, height) != 0) {
      throw std::runtime_error("External BGRA conversion failed");
    }
    first = {converted.data(), ySize, width};
    second = {converted.data() + ySize, ySize / 2, width};
  } else {
    ValidatePlane(second, width, height / 2);
  }

  if (libyuv::NV12Scale(first.data, first.stride, second.data, second.stride, width, height,
      output, outputWidth, output + static_cast<size_t>(outputWidth) * outputHeight, outputWidth,
      outputWidth, outputHeight, libyuv::kFilterBilinear) != 0) {
    throw std::runtime_error("External video scaling failed");
  }
}
} // namespace xmax
