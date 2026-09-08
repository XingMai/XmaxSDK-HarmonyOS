#ifndef XMAX_LIBYUV_FRAME_CONVERTER_H
#define XMAX_LIBYUV_FRAME_CONVERTER_H

#include <cstdint>
#include <memory>

#include "video_frame_geometry.h"

namespace xmax {
namespace internal {
class LibyuvFrameTransformer {
 public:
  LibyuvFrameTransformer();
  ~LibyuvFrameTransformer();

  LibyuvFrameTransformer(const LibyuvFrameTransformer&) = delete;
  LibyuvFrameTransformer& operator=(const LibyuvFrameTransformer&) = delete;

  bool TransformNv21ToNv12(
      const uint8_t* sourceLuma,
      const uint8_t* sourceChroma,
      uint8_t* destination,
      const VideoFrameTransformGeometry& geometry,
      VideoFrameConversionTiming* timing = nullptr);

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};
}  // namespace internal
}  // namespace xmax

#endif
