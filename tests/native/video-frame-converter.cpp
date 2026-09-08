#include <algorithm>
#include <cassert>
#include <cmath>
#include <chrono>
#include <cstdint>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

#include "video_frame_converter.h"
#include "video_frame_geometry.h"
#include "libyuv/planar_functions.h"
#include "libyuv/rotate.h"
#include "libyuv/scale.h"
#include "libyuv/cpu_id.h"

using xmax::VideoFrameTransformConfiguration;
using xmax::VideoFrameTransformer;

struct Input {
  explicit Input(const VideoFrameTransformConfiguration& c, uint8_t padding = 253)
      : y(c.sourceStride * c.sourceHeight, padding),
        vu(c.sourceChromaStride * c.sourceHeight / 2, padding) {
    for (int row = 0; row < c.sourceHeight; ++row) {
      for (int col = 0; col < c.sourceWidth; ++col) {
        y[row * c.sourceStride + col] = (row * 7 + col * 3) % 251;
      }
    }
    for (int row = 0; row < c.sourceHeight / 2; ++row) {
      for (int col = 0; col < c.sourceWidth / 2; ++col) {
        vu[row * c.sourceChromaStride + col * 2] = 170 + (row + col) % 50;
        vu[row * c.sourceChromaStride + col * 2 + 1] = 20 + (row * 2 + col) % 50;
      }
    }
  }
  std::vector<uint8_t> y, vu;
};

// Frozen reference for the original copy -> scale -> rotate -> copy pipeline.
// Keep the intermediate Y planes here to detect changes from direct source/output access.
struct ReferenceI420 {
  ReferenceI420(int width, int height) : w(width), h(height), data(w * h * 3 / 2) {}
  uint8_t* y() { return data.data(); }
  uint8_t* u() { return data.data() + w * h; }
  uint8_t* v() { return data.data() + w * h * 5 / 4; }
  int w, h;
  std::vector<uint8_t> data;
};

std::vector<uint8_t> CopyingReference(const Input& input, const VideoFrameTransformConfiguration& c) {
  const auto geometry = xmax::internal::MakeVideoFrameTransformGeometry(c);
  const auto even = [](double value) { return static_cast<int>(std::floor(value)) & ~1; };
  const int cw = std::clamp(even(geometry.sourceCrop.width), 2, c.sourceWidth & ~1);
  const int ch = std::clamp(even(geometry.sourceCrop.height), 2, c.sourceHeight & ~1);
  const int cx = std::clamp(even(geometry.sourceCrop.x), 0, (c.sourceWidth - cw) & ~1);
  const int cy = std::clamp(even(geometry.sourceCrop.y), 0, (c.sourceHeight - ch) & ~1);
  const bool swap = c.rotation == 90 || c.rotation == 270;
  ReferenceI420 cropped(cw, ch), scaled(swap ? c.targetHeight : c.targetWidth,
                                      swap ? c.targetWidth : c.targetHeight);
  ReferenceI420 rotated(c.targetWidth, c.targetHeight);
  libyuv::CopyPlane(input.y.data() + cy * c.sourceStride + cx, c.sourceStride,
                    cropped.y(), cw, cw, ch);
  libyuv::SplitUVPlane(input.vu.data() + cy / 2 * c.sourceChromaStride + cx, c.sourceChromaStride,
                       cropped.v(), cw / 2, cropped.u(), cw / 2, cw / 2, ch / 2);
  assert(libyuv::I420Scale(cropped.y(), cw, cropped.u(), cw / 2, cropped.v(), cw / 2, cw, ch,
                          scaled.y(), scaled.w, scaled.u(), scaled.w / 2, scaled.v(), scaled.w / 2,
                          scaled.w, scaled.h, libyuv::kFilterBilinear) == 0);
  ReferenceI420* final = &scaled;
  if (c.rotation != 0) {
    assert(libyuv::I420Rotate(scaled.y(), scaled.w, scaled.u(), scaled.w / 2,
                             scaled.v(), scaled.w / 2, rotated.y(), rotated.w,
                             rotated.u(), rotated.w / 2, rotated.v(), rotated.w / 2,
                             scaled.w, scaled.h, static_cast<libyuv::RotationMode>(c.rotation)) == 0);
    final = &rotated;
  }
  std::vector<uint8_t> out(c.targetWidth * c.targetHeight * 3 / 2);
  libyuv::CopyPlane(final->y(), final->w, out.data(), c.targetWidth, c.targetWidth, c.targetHeight);
  libyuv::MergeUVPlane(final->u(), final->w / 2, final->v(), final->w / 2,
                       out.data() + c.targetWidth * c.targetHeight, c.targetWidth,
                       c.targetWidth / 2, c.targetHeight / 2);
  return out;
}

std::vector<uint8_t> Convert(VideoFrameTransformer& converter, const Input& input,
                             const VideoFrameTransformConfiguration& c) {
  const size_t size = c.targetWidth * c.targetHeight * 3 / 2;
  std::vector<uint8_t> guarded(size + 64, 0xdd);
  const auto startedAt = std::chrono::steady_clock::now();
  converter.TransformNv21ToNv12(input.y.data(), input.vu.data(), guarded.data() + 32, c);
  const double elapsedMs = std::chrono::duration<double, std::milli>(
      std::chrono::steady_clock::now() - startedAt).count();
  const auto& timing = converter.timing();
  assert(timing.valid);
  double stageTotal = 0;
  for (double value : {timing.uvSplitMilliseconds, timing.scaleMilliseconds,
                       timing.rotationMilliseconds, timing.uvMergeMilliseconds}) {
    assert(std::isfinite(value) && value >= 0);
    stageTotal += value;
  }
  assert(stageTotal <= elapsedMs + 0.000001);
  if (c.rotation == 0) assert(timing.rotationMilliseconds == 0);
  assert(std::all_of(guarded.begin(), guarded.begin() + 32, [](uint8_t v) { return v == 0xdd; }));
  assert(std::all_of(guarded.end() - 32, guarded.end(), [](uint8_t v) { return v == 0xdd; }));
  assert(std::string(converter.backend()).find("libyuv") == 0);
  std::vector<uint8_t> output(guarded.begin() + 32, guarded.end() - 32);
  assert(output == CopyingReference(input, c));
  // Different initial bytes must produce identical output. This detects every
  // unwritten byte when production uses an uninitialized allocation.
  std::unique_ptr<uint8_t[]> reused(new uint8_t[size]);
  std::fill_n(reused.get(), size, 0x22);
  converter.TransformNv21ToNv12(input.y.data(), input.vu.data(), reused.get(), c);
  assert(std::equal(output.begin(), output.end(), reused.get()));
  return output;
}

void CheckExactRotationAndCrop() {
  VideoFrameTransformer converter;
  for (int rotation : {0, 90, 180, 270}) {
    // Crop a centered 8x12 area from a padded 16x12 frame, without scaling.
    const bool swap = rotation == 90 || rotation == 270;
    VideoFrameTransformConfiguration c{16, 12, 23, 28, rotation, swap ? 12 : 8, swap ? 8 : 12};
    Input input(c);
    auto output = Convert(converter, input, c);
    for (int plane = 0; plane < 2; ++plane) {
      const int divisor = plane ? 2 : 1;
      const int width = c.targetWidth / divisor, height = c.targetHeight / divisor;
      const int cropWidth = 8 / divisor, cropHeight = 12 / divisor;
      for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
          int sx = x, sy = y;
          if (rotation == 90) { sx = y; sy = cropHeight - 1 - x; }
          if (rotation == 180) { sx = cropWidth - 1 - x; sy = cropHeight - 1 - y; }
          if (rotation == 270) { sx = cropWidth - 1 - y; sy = x; }
          sx += 4 / divisor;
          if (!plane) {
            assert(output[y * width + x] == input.y[sy * c.sourceStride + sx]);
          } else {
            const int offset = c.targetWidth * c.targetHeight + y * c.targetWidth + x * 2;
            assert(output[offset] == input.vu[sy * c.sourceChromaStride + sx * 2 + 1]);
            assert(output[offset + 1] == input.vu[sy * c.sourceChromaStride + sx * 2]);
          }
        }
      }
    }
  }
}

void CheckScalingAndReconfiguration() {
  VideoFrameTransformer reused;
  const std::vector<VideoFrameTransformConfiguration> cases{
    {1920, 1440, 1984, 2048, 90, 1024, 1920},
    {1440, 1080, 1472, 1536, 270, 832, 1472},
    {1920, 1440, 1920, 1920, 0, 1024, 1920},
    {1440, 1080, 1440, 1440, 180, 832, 1472},
    {18, 14, 25, 30, 90, 10, 22},
    {18, 14, 18, 18, 270, 26, 10},
    {2, 2, 2, 2, 0, 2, 2},
    {2, 2, 2, 2, 90, 6, 4},
    {1920, 1440, 1984, 2048, 90, 1024, 1920}
  };
  for (const auto& c : cases) {
    Input input(c), otherPadding(c, 0);
    libyuv::MaskCpuFlags(-1);
    auto accelerated = Convert(reused, input, c);
    // Padding must never affect visible output; repeat calls exercise cached buffers.
    assert(accelerated == Convert(reused, otherPadding, c));
    libyuv::MaskCpuFlags(1);
    VideoFrameTransformer reference;
    auto scalarLibyuv = Convert(reference, input, c);
    assert(std::string(reference.backend()) == "libyuv (C)");
    for (size_t i = 0; i < accelerated.size(); ++i) {
      assert(std::abs(int(accelerated[i]) - int(scalarLibyuv[i])) <= 2);
    }
    // Constant planes catch UV swaps, uninitialized pixels and edge artifacts.
    std::fill(input.y.begin(), input.y.end(), 81);
    for (size_t i = 0; i < input.vu.size(); i += 2) {
      input.vu[i] = 173;
      input.vu[i + 1] = 43;
    }
    libyuv::MaskCpuFlags(-1);
    auto constant = Convert(reused, input, c);
    const size_t luma = c.targetWidth * c.targetHeight;
    for (size_t i = 0; i < luma; ++i) assert(constant[i] == 81);
    for (size_t i = luma; i < constant.size(); i += 2) {
      assert(constant[i] == 43 && constant[i + 1] == 173);
    }
  }
}

void CheckInvalidConfiguration() {
  const VideoFrameTransformConfiguration valid{4, 4, 4, 4, 0, 4, 4};
  const Input input(valid);
  VideoFrameTransformer converter;
  Convert(converter, input, valid);
  std::vector<uint8_t> output(24, 0xcd);
  const auto expectInvalid = [&](const VideoFrameTransformConfiguration& c,
                                 const uint8_t* y, const uint8_t* vu, uint8_t* destination) {
    bool rejected = false;
    try {
      converter.TransformNv21ToNv12(y, vu, destination, c);
    } catch (const std::invalid_argument&) {
      rejected = true;
    }
    assert(rejected && !converter.timing().valid);
    assert(std::all_of(output.begin(), output.end(), [](uint8_t value) { return value == 0xcd; }));
  };
  expectInvalid(valid, nullptr, input.vu.data(), output.data());
  expectInvalid(valid, input.y.data(), nullptr, output.data());
  expectInvalid(valid, input.y.data(), input.vu.data(), nullptr);
  for (int field = 0; field < 7; ++field) {
    auto c = valid;
    switch (field) {
      case 0: c.sourceWidth = 0; break;
      case 1: c.sourceHeight = -2; break;
      case 2: c.sourceStride = -1; break;
      case 3: c.sourceChromaStride = 2; break;
      case 4: c.rotation = 45; break;
      case 5: c.targetWidth = 3; break;
      case 6: c.targetHeight = 32770; break;
    }
    expectInvalid(c, input.y.data(), input.vu.data(), output.data());
  }
  // A rejected frame must not poison the cached transform plan.
  Convert(converter, input, valid);
}

int main() {
  assert(libyuv::TestCpuFlag(libyuv::kCpuHasNEON));
  CheckExactRotationAndCrop();
  CheckScalingAndReconfiguration();
  CheckInvalidConfiguration();
  std::cout << "NEON conversion: byte-exact copy-pipeline equivalence, crop, rotations, UV order, strides, scaling and reconfiguration passed\n";
}
