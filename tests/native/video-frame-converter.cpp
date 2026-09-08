#include <algorithm>
#include <cassert>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <vector>

#include "video_frame_converter.h"
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

std::vector<uint8_t> Convert(VideoFrameTransformer& converter, const Input& input,
                             const VideoFrameTransformConfiguration& c) {
  const size_t size = c.targetWidth * c.targetHeight * 3 / 2;
  std::vector<uint8_t> guarded(size + 64, 0xdd);
  converter.TransformNv21ToNv12(input.y.data(), input.vu.data(), guarded.data() + 32, c);
  assert(std::all_of(guarded.begin(), guarded.begin() + 32, [](uint8_t v) { return v == 0xdd; }));
  assert(std::all_of(guarded.end() - 32, guarded.end(), [](uint8_t v) { return v == 0xdd; }));
  return {guarded.begin() + 32, guarded.end() - 32};
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

int main() {
  assert(libyuv::TestCpuFlag(libyuv::kCpuHasNEON));
  CheckExactRotationAndCrop();
  CheckScalingAndReconfiguration();
  std::cout << "NEON conversion: crop, rotations, UV order, strides, scaling and reconfiguration passed\n";
}
