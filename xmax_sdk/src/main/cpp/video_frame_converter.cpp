#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <vector>

#include "video_frame_converter.h"
#include "video_frame_geometry.h"

namespace {
using xmax::internal::VideoFrameTransformGeometry;

struct AxisSample {
  int32_t low;
  int32_t high;
  uint32_t weight;
};

struct RotationCoordinateMapping {
  int32_t sourceXOrigin;
  int32_t sourceYOrigin;
  int32_t sourceXXStep;
  int32_t sourceYXStep;
  int32_t sourceXYStep;
  int32_t sourceYYStep;
};

constexpr uint32_t kInterpolationScale = 1U << 14;

double MapCoordinate(
    int32_t index,
    int32_t targetLength,
    double cropOffset,
    double cropLength,
    int32_t sourceLength) {
  const double scale = cropLength / static_cast<double>(targetLength);
  return std::clamp(
      cropOffset + (static_cast<double>(index) + 0.5) * scale - 0.5,
      0.0,
      static_cast<double>(sourceLength - 1));
}

std::vector<AxisSample> MakeAxisSamples(
    int32_t targetLength,
    double cropOffset,
    double cropLength,
    int32_t sourceLength) {
  std::vector<AxisSample> samples;
  samples.reserve(static_cast<size_t>(targetLength));

  for (int32_t index = 0; index < targetLength; ++index) {
    const double coordinate = MapCoordinate(
        index,
        targetLength,
        cropOffset,
        cropLength,
        sourceLength);
    const int32_t low = static_cast<int32_t>(coordinate);
    const int32_t high = std::min(low + 1, sourceLength - 1);
    const uint32_t weight = low == high ? 0 : static_cast<uint32_t>(
        std::lround(
            (coordinate - static_cast<double>(low)) *
                static_cast<double>(kInterpolationScale)));
    samples.push_back({low, high, weight});
  }

  return samples;
}

std::vector<int32_t> MakeNearestSamples(
    int32_t targetLength,
    double cropOffset,
    double cropLength,
    int32_t sourceLength) {
  std::vector<int32_t> samples;
  samples.reserve(static_cast<size_t>(targetLength));

  for (int32_t index = 0; index < targetLength; ++index) {
    const double coordinate = MapCoordinate(
        index,
        targetLength,
        cropOffset,
        cropLength,
        sourceLength);
    const int32_t low = static_cast<int32_t>(coordinate);
    const int32_t high = std::min(low + 1, sourceLength - 1);
    const uint32_t weight = low == high ? 0 : static_cast<uint32_t>(
        std::lround(
            (coordinate - static_cast<double>(low)) *
                static_cast<double>(kInterpolationScale)));
    samples.push_back(
        weight < kInterpolationScale / 2 ? low : high);
  }

  return samples;
}

bool MatchesConfiguration(
    const VideoFrameTransformGeometry& geometry,
    const xmax::VideoFrameTransformConfiguration& configuration) {
  return geometry.sourceWidth == configuration.sourceWidth &&
      geometry.sourceHeight == configuration.sourceHeight &&
      geometry.sourceStride == configuration.sourceStride &&
      geometry.sourceChromaStride == configuration.sourceChromaStride &&
      geometry.rotation == configuration.rotation &&
      geometry.targetWidth == configuration.targetWidth &&
      geometry.targetHeight == configuration.targetHeight;
}

struct TransformPlan {
  explicit TransformPlan(
      const VideoFrameTransformGeometry& frameGeometry)
      : geometry(frameGeometry) {
    const bool swapsDimensions = geometry.rotation == 90 ||
        geometry.rotation == 270;
    scaledWidth = swapsDimensions ?
        geometry.targetHeight : geometry.targetWidth;
    scaledHeight = swapsDimensions ?
        geometry.targetWidth : geometry.targetHeight;
    targetLumaLength = static_cast<size_t>(geometry.targetWidth) *
        static_cast<size_t>(geometry.targetHeight);

    lumaXSamples = MakeAxisSamples(
        scaledWidth,
        geometry.sourceCrop.x,
        geometry.sourceCrop.width,
        geometry.sourceWidth);
    lumaYSamples = MakeAxisSamples(
        scaledHeight,
        geometry.sourceCrop.y,
        geometry.sourceCrop.height,
        geometry.sourceHeight);
    firstSourceY = lumaYSamples.front().low;
    const int32_t lastSourceY = lumaYSamples.back().high;
    const int32_t horizontalHeight = lastSourceY - firstSourceY + 1;
    horizontalFrame.resize(
        static_cast<size_t>(scaledWidth) *
            static_cast<size_t>(horizontalHeight));

    chromaXSamples = MakeNearestSamples(
        scaledWidth / 2,
        geometry.sourceCrop.x / 2.0,
        geometry.sourceCrop.width / 2.0,
        geometry.sourceWidth / 2);
    chromaYSamples = MakeNearestSamples(
        scaledHeight / 2,
        geometry.sourceCrop.y / 2.0,
        geometry.sourceCrop.height / 2.0,
        geometry.sourceHeight / 2);
  }

  VideoFrameTransformGeometry geometry;
  int32_t scaledWidth = 0;
  int32_t scaledHeight = 0;
  size_t targetLumaLength = 0;
  int32_t firstSourceY = 0;
  std::vector<AxisSample> lumaXSamples;
  std::vector<AxisSample> lumaYSamples;
  std::vector<int32_t> chromaXSamples;
  std::vector<int32_t> chromaYSamples;
  std::vector<uint8_t> horizontalFrame;
};

RotationCoordinateMapping MakeRotationCoordinateMapping(
    int32_t rotation,
    int32_t sourceWidth,
    int32_t sourceHeight) {
  switch (rotation) {
    case 90:
      return {
          0,
          sourceHeight - 1,
          0,
          -1,
          1,
          0
      };
    case 180:
      return {
          sourceWidth - 1,
          sourceHeight - 1,
          -1,
          0,
          0,
          -1
      };
    case 270:
      return {
          sourceWidth - 1,
          0,
          0,
          1,
          -1,
          0
      };
    default:
      return {
          0,
          0,
          1,
          0,
          0,
          1
      };
  }
}

uint8_t InterpolateLine(
    uint8_t first,
    uint8_t second,
    uint32_t weight) {
  return static_cast<uint8_t>((
      static_cast<uint32_t>(first) * (kInterpolationScale - weight) +
      static_cast<uint32_t>(second) * weight +
      kInterpolationScale / 2) / kInterpolationScale);
}

void ScaleLuma(
    const uint8_t* source,
    uint8_t* destination,
    TransformPlan* plan) {
  const int32_t scaledWidth = plan->scaledWidth;
  const int32_t firstSourceY = plan->firstSourceY;
  const int32_t lastSourceY = plan->lumaYSamples.back().high;

  for (int32_t sourceY = firstSourceY; sourceY <= lastSourceY; ++sourceY) {
    const uint8_t* sourceRow = source +
        static_cast<size_t>(sourceY) *
            static_cast<size_t>(plan->geometry.sourceStride);
    uint8_t* horizontalRow = plan->horizontalFrame.data() +
        static_cast<size_t>(sourceY - firstSourceY) *
            static_cast<size_t>(scaledWidth);
    for (int32_t scaledX = 0; scaledX < scaledWidth; ++scaledX) {
      const AxisSample& xSample =
          plan->lumaXSamples[static_cast<size_t>(scaledX)];
      horizontalRow[scaledX] = InterpolateLine(
          sourceRow[xSample.low],
          sourceRow[xSample.high],
          xSample.weight);
    }
  }

  const int32_t targetWidth = plan->geometry.targetWidth;
  const int32_t targetHeight = plan->geometry.targetHeight;
  const RotationCoordinateMapping mapping = MakeRotationCoordinateMapping(
      plan->geometry.rotation,
      plan->scaledWidth,
      plan->scaledHeight);

  for (int32_t targetY = 0; targetY < targetHeight; ++targetY) {
    uint8_t* targetRow = destination +
        static_cast<size_t>(targetY) * static_cast<size_t>(targetWidth);
    int32_t scaledX = mapping.sourceXOrigin +
        targetY * mapping.sourceXYStep;
    int32_t scaledY = mapping.sourceYOrigin +
        targetY * mapping.sourceYYStep;

    for (int32_t targetX = 0; targetX < targetWidth; ++targetX) {
      const AxisSample& ySample =
          plan->lumaYSamples[static_cast<size_t>(scaledY)];
      const uint8_t* topRow = plan->horizontalFrame.data() +
          static_cast<size_t>(ySample.low - firstSourceY) *
              static_cast<size_t>(scaledWidth);
      const uint8_t* bottomRow = plan->horizontalFrame.data() +
          static_cast<size_t>(ySample.high - firstSourceY) *
              static_cast<size_t>(scaledWidth);
      targetRow[targetX] = InterpolateLine(
          topRow[scaledX],
          bottomRow[scaledX],
          ySample.weight);
      scaledX += mapping.sourceXXStep;
      scaledY += mapping.sourceYXStep;
    }
  }
}

void ScaleChroma(
    const uint8_t* sourceChroma,
    uint8_t* destination,
    const TransformPlan& plan) {
  uint8_t* targetChroma = destination + plan.targetLumaLength;
  const int32_t targetWidth = plan.geometry.targetWidth;
  const int32_t targetHeight = plan.geometry.targetHeight;
  const int32_t targetChromaWidth = targetWidth / 2;
  const int32_t targetChromaHeight = targetHeight / 2;
  const int32_t scaledChromaWidth = plan.scaledWidth / 2;
  const int32_t scaledChromaHeight = plan.scaledHeight / 2;
  const RotationCoordinateMapping mapping = MakeRotationCoordinateMapping(
      plan.geometry.rotation,
      scaledChromaWidth,
      scaledChromaHeight);

  for (int32_t targetY = 0; targetY < targetChromaHeight; ++targetY) {
    uint8_t* targetRow = targetChroma +
        static_cast<size_t>(targetY) * static_cast<size_t>(targetWidth);
    int32_t scaledX = mapping.sourceXOrigin +
        targetY * mapping.sourceXYStep;
    int32_t scaledY = mapping.sourceYOrigin +
        targetY * mapping.sourceYYStep;

    for (int32_t targetX = 0; targetX < targetChromaWidth; ++targetX) {
      const int32_t sourceY =
          plan.chromaYSamples[static_cast<size_t>(scaledY)];
      const uint8_t* sourceRow = sourceChroma +
          static_cast<size_t>(sourceY) *
              static_cast<size_t>(plan.geometry.sourceChromaStride);
      const int32_t sourceX =
          plan.chromaXSamples[static_cast<size_t>(scaledX)];
      const size_t sourceIndex = static_cast<size_t>(sourceX) * 2;
      const size_t targetIndex = static_cast<size_t>(targetX) * 2;

      targetRow[targetIndex] = sourceRow[sourceIndex + 1];
      targetRow[targetIndex + 1] = sourceRow[sourceIndex];
      scaledX += mapping.sourceXXStep;
      scaledY += mapping.sourceYXStep;
    }
  }
}

void TransformFrame(
    const uint8_t* sourceLuma,
    const uint8_t* sourceChroma,
    uint8_t* destination,
    TransformPlan* plan) {
  ScaleLuma(
      sourceLuma,
      destination,
      plan);
  ScaleChroma(
      sourceChroma,
      destination,
      *plan);
}

}  // namespace

namespace xmax {
class VideoFrameTransformer::Impl {
 public:
  std::unique_ptr<internal::VideoFrameTransformGeometry> geometry;
  std::unique_ptr<TransformPlan> fallbackPlan;
};

VideoFrameTransformer::VideoFrameTransformer()
    : impl_(std::make_unique<Impl>()) {}

VideoFrameTransformer::~VideoFrameTransformer() = default;

void VideoFrameTransformer::TransformNv21ToNv12(
    const uint8_t* sourceLuma,
    const uint8_t* sourceChroma,
    uint8_t* destination,
    const VideoFrameTransformConfiguration& configuration) {
  if (impl_->geometry == nullptr ||
      !MatchesConfiguration(*impl_->geometry, configuration)) {
    impl_->geometry =
        std::make_unique<internal::VideoFrameTransformGeometry>(
            internal::MakeVideoFrameTransformGeometry(configuration));
    impl_->fallbackPlan.reset();
  }

  if (impl_->fallbackPlan == nullptr) {
    impl_->fallbackPlan = std::make_unique<TransformPlan>(*impl_->geometry);
  }

  TransformFrame(
      sourceLuma,
      sourceChroma,
      destination,
      impl_->fallbackPlan.get());
}
}  // namespace xmax
