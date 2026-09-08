#ifndef XMAX_VIDEO_FRAME_CONVERTER_H
#define XMAX_VIDEO_FRAME_CONVERTER_H

#include <cstdint>
#include <memory>

namespace xmax {
struct VideoFrameTransformConfiguration {
  int32_t sourceWidth;
  int32_t sourceHeight;
  int32_t sourceStride;
  int32_t sourceChromaStride;
  int32_t rotation;
  int32_t targetWidth;
  int32_t targetHeight;
};

struct VideoFrameConversionTiming {
  bool valid = false;
  double uvSplitMilliseconds = 0.0;
  double scaleMilliseconds = 0.0;
  double rotationMilliseconds = 0.0;
  double uvMergeMilliseconds = 0.0;
};

class VideoFrameTransformer {
 public:
  VideoFrameTransformer();
  ~VideoFrameTransformer();

  VideoFrameTransformer(const VideoFrameTransformer&) = delete;
  VideoFrameTransformer& operator=(const VideoFrameTransformer&) = delete;

  // Requires even dimensions in [2, 32768], valid strides and a quarter-turn
  // rotation. Invalid input or a libyuv failure throws before delivery.
  void TransformNv21ToNv12(
      const uint8_t* sourceLuma,
      const uint8_t* sourceChroma,
      uint8_t* destination,
      const VideoFrameTransformConfiguration& configuration);

  // Backend used by the most recent frame; for capture performance diagnostics.
  const char* backend() const;
  const VideoFrameConversionTiming& timing() const;

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};
}  // namespace xmax

#endif
