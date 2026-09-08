#include "video_frame_geometry.h"

namespace xmax {
namespace internal {
VideoFrameTransformGeometry MakeVideoFrameTransformGeometry(
    const VideoFrameTransformConfiguration& configuration) {
  const bool swapsDimensions = configuration.rotation == 90 ||
      configuration.rotation == 270;
  const double orientedWidth = static_cast<double>(
      swapsDimensions ? configuration.sourceHeight :
          configuration.sourceWidth);
  const double orientedHeight = static_cast<double>(
      swapsDimensions ? configuration.sourceWidth :
          configuration.sourceHeight);
  const double targetAspect = static_cast<double>(
      configuration.targetWidth) /
      static_cast<double>(configuration.targetHeight);

  double cropWidth = orientedWidth;
  double cropHeight = orientedHeight;
  if (orientedWidth / orientedHeight > targetAspect) {
    cropWidth = orientedHeight * targetAspect;
  } else {
    cropHeight = orientedWidth / targetAspect;
  }

  const double cropX = (orientedWidth - cropWidth) / 2.0;
  const double cropY = (orientedHeight - cropHeight) / 2.0;
  VideoFrameCropGeometry sourceCrop;
  switch (configuration.rotation) {
    case 90:
      sourceCrop = {
          cropY,
          static_cast<double>(configuration.sourceHeight) -
              cropX - cropWidth,
          cropHeight,
          cropWidth
      };
      break;
    case 180:
      sourceCrop = {
          static_cast<double>(configuration.sourceWidth) -
              cropX - cropWidth,
          static_cast<double>(configuration.sourceHeight) -
              cropY - cropHeight,
          cropWidth,
          cropHeight
      };
      break;
    case 270:
      sourceCrop = {
          static_cast<double>(configuration.sourceWidth) -
              cropY - cropHeight,
          cropX,
          cropHeight,
          cropWidth
      };
      break;
    default:
      sourceCrop = {cropX, cropY, cropWidth, cropHeight};
      break;
  }

  return {
      configuration.sourceWidth,
      configuration.sourceHeight,
      configuration.sourceStride,
      configuration.sourceChromaStride,
      configuration.rotation,
      configuration.targetWidth,
      configuration.targetHeight,
      sourceCrop
  };
}
}  // namespace internal
}  // namespace xmax
