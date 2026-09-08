#ifndef XMAX_VIDEO_FRAME_GEOMETRY_H
#define XMAX_VIDEO_FRAME_GEOMETRY_H

#include <cstdint>

#include "video_frame_converter.h"

namespace xmax {
namespace internal {
struct VideoFrameCropGeometry {
  double x;
  double y;
  double width;
  double height;
};

struct VideoFrameTransformGeometry {
  int32_t sourceWidth;
  int32_t sourceHeight;
  int32_t sourceStride;
  int32_t sourceChromaStride;
  int32_t rotation;
  int32_t targetWidth;
  int32_t targetHeight;
  VideoFrameCropGeometry sourceCrop;
};

VideoFrameTransformGeometry MakeVideoFrameTransformGeometry(
    const VideoFrameTransformConfiguration& configuration);
}  // namespace internal
}  // namespace xmax

#endif
