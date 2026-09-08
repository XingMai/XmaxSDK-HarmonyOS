#include "libyuv_frame_converter.h"

#include <algorithm>
#include <cmath>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <vector>

#include "libyuv/planar_functions.h"
#include "libyuv/rotate.h"
#include "libyuv/scale.h"

namespace {
bool MatchesGeometry(
    const xmax::internal::VideoFrameTransformGeometry& left,
    const xmax::internal::VideoFrameTransformGeometry& right) {
  return left.sourceWidth == right.sourceWidth &&
      left.sourceHeight == right.sourceHeight &&
      left.sourceStride == right.sourceStride &&
      left.sourceChromaStride == right.sourceChromaStride &&
      left.rotation == right.rotation &&
      left.targetWidth == right.targetWidth &&
      left.targetHeight == right.targetHeight;
}

int32_t FloorToEven(double value) {
  return static_cast<int32_t>(std::floor(value)) & ~1;
}

int32_t ClampEvenLength(double value, int32_t maximum) {
  const int32_t evenMaximum = maximum & ~1;
  return std::clamp(FloorToEven(value), 2, evenMaximum);
}

int32_t ClampEvenOffset(
    double value,
    int32_t maximum) {
  return std::clamp(FloorToEven(value), 0, maximum & ~1);
}

libyuv::RotationMode ToRotationMode(int32_t rotation) {
  switch (rotation) {
    case 90:
      return libyuv::kRotate90;
    case 180:
      return libyuv::kRotate180;
    case 270:
      return libyuv::kRotate270;
    default:
      return libyuv::kRotate0;
  }
}

class I420Buffer {
 public:
  void Reset(
      int32_t width,
      int32_t height,
      bool allocateLuma) {
    width_ = width;
    height_ = height;
    chromaWidth_ = (width + 1) / 2;
    chromaHeight_ = (height + 1) / 2;

    // Converted/rotated Y is read from the source or written directly to the
    // caller. Only allocate intermediate Y when a separate rotation is needed.
    const size_t lumaLength = allocateLuma ? static_cast<size_t>(width_) *
        static_cast<size_t>(height_) : 0;
    const size_t chromaLength = static_cast<size_t>(chromaWidth_) *
        static_cast<size_t>(chromaHeight_);
    data_.resize(lumaLength + chromaLength * 2);
    uOffset_ = lumaLength;
    vOffset_ = lumaLength + chromaLength;
  }

  int32_t width() const {
    return width_;
  }

  int32_t height() const {
    return height_;
  }

  int32_t chromaStride() const {
    return chromaWidth_;
  }

  uint8_t* y() {
    return uOffset_ == 0 ? nullptr : data_.data();
  }

  const uint8_t* y() const {
    return uOffset_ == 0 ? nullptr : data_.data();
  }

  uint8_t* u() {
    return data_.data() + uOffset_;
  }

  const uint8_t* u() const {
    return data_.data() + uOffset_;
  }

  uint8_t* v() {
    return data_.data() + vOffset_;
  }

  const uint8_t* v() const {
    return data_.data() + vOffset_;
  }

 private:
  int32_t width_ = 0;
  int32_t height_ = 0;
  int32_t chromaWidth_ = 0;
  int32_t chromaHeight_ = 0;
  size_t uOffset_ = 0;
  size_t vOffset_ = 0;
  std::vector<uint8_t> data_;
};

struct LibyuvTransformPlan {
  explicit LibyuvTransformPlan(
      const xmax::internal::VideoFrameTransformGeometry& frameGeometry)
      : geometry(frameGeometry) {
    cropWidth = ClampEvenLength(
        geometry.sourceCrop.width,
        geometry.sourceWidth);
    cropHeight = ClampEvenLength(
        geometry.sourceCrop.height,
        geometry.sourceHeight);
    cropX = ClampEvenOffset(
        geometry.sourceCrop.x,
        geometry.sourceWidth - cropWidth);
    cropY = ClampEvenOffset(
        geometry.sourceCrop.y,
        geometry.sourceHeight - cropHeight);

    const bool swapsDimensions = geometry.rotation == 90 ||
        geometry.rotation == 270;
    const int32_t scaledWidth = swapsDimensions ?
        geometry.targetHeight : geometry.targetWidth;
    const int32_t scaledHeight = swapsDimensions ?
        geometry.targetWidth : geometry.targetHeight;

    convertedFrame.Reset(cropWidth, cropHeight, false);
    scaledFrame.Reset(scaledWidth, scaledHeight, geometry.rotation != 0);
    if (geometry.rotation != 0) {
      rotatedFrame.Reset(
          geometry.targetWidth,
          geometry.targetHeight,
          false);
    }
  }

  const I420Buffer& finalFrame() const {
    return geometry.rotation == 0 ? scaledFrame : rotatedFrame;
  }

  xmax::internal::VideoFrameTransformGeometry geometry;
  int32_t cropX = 0;
  int32_t cropY = 0;
  int32_t cropWidth = 0;
  int32_t cropHeight = 0;
  I420Buffer convertedFrame;
  I420Buffer scaledFrame;
  I420Buffer rotatedFrame;
};

void SplitSourceChroma(
    const uint8_t* sourceChroma,
    LibyuvTransformPlan* plan) {
  const uint8_t* croppedChroma = sourceChroma +
      static_cast<size_t>(plan->cropY / 2) *
          static_cast<size_t>(plan->geometry.sourceChromaStride) +
      static_cast<size_t>(plan->cropX);

  libyuv::SplitUVPlane(
      croppedChroma,
      plan->geometry.sourceChromaStride,
      plan->convertedFrame.v(),
      plan->convertedFrame.chromaStride(),
      plan->convertedFrame.u(),
      plan->convertedFrame.chromaStride(),
      plan->cropWidth / 2,
      plan->cropHeight / 2);
}

bool ScaleFrame(
    const uint8_t* sourceLuma,
    uint8_t* destination,
    LibyuvTransformPlan* plan) {
  const uint8_t* croppedLuma = sourceLuma +
      static_cast<size_t>(plan->cropY) *
          static_cast<size_t>(plan->geometry.sourceStride) +
      static_cast<size_t>(plan->cropX);
  uint8_t* scaledLuma = plan->geometry.rotation == 0 ?
      destination : plan->scaledFrame.y();
  return libyuv::I420Scale(
      croppedLuma,
      plan->geometry.sourceStride,
      plan->convertedFrame.u(),
      plan->convertedFrame.chromaStride(),
      plan->convertedFrame.v(),
      plan->convertedFrame.chromaStride(),
      plan->convertedFrame.width(),
      plan->convertedFrame.height(),
      scaledLuma,
      plan->scaledFrame.width(),
      plan->scaledFrame.u(),
      plan->scaledFrame.chromaStride(),
      plan->scaledFrame.v(),
      plan->scaledFrame.chromaStride(),
      plan->scaledFrame.width(),
      plan->scaledFrame.height(),
      libyuv::kFilterBilinear) == 0;
}

bool RotateFrame(uint8_t* destination, LibyuvTransformPlan* plan) {
  if (plan->geometry.rotation == 0) {
    return true;
  }

  return libyuv::I420Rotate(
      plan->scaledFrame.y(),
      plan->scaledFrame.width(),
      plan->scaledFrame.u(),
      plan->scaledFrame.chromaStride(),
      plan->scaledFrame.v(),
      plan->scaledFrame.chromaStride(),
      destination,
      plan->geometry.targetWidth,
      plan->rotatedFrame.u(),
      plan->rotatedFrame.chromaStride(),
      plan->rotatedFrame.v(),
      plan->rotatedFrame.chromaStride(),
      plan->scaledFrame.width(),
      plan->scaledFrame.height(),
      ToRotationMode(plan->geometry.rotation)) == 0;
}

void WriteNv12Chroma(
    uint8_t* destination,
    const LibyuvTransformPlan& plan) {
  const I420Buffer& frame = plan.finalFrame();
  uint8_t* destinationChroma = destination +
      static_cast<size_t>(plan.geometry.targetWidth) *
          static_cast<size_t>(plan.geometry.targetHeight);

  libyuv::MergeUVPlane(
      frame.u(),
      frame.chromaStride(),
      frame.v(),
      frame.chromaStride(),
      destinationChroma,
      plan.geometry.targetWidth,
      plan.geometry.targetWidth / 2,
      plan.geometry.targetHeight / 2);
}
}  // namespace

namespace xmax {
namespace internal {
class LibyuvFrameTransformer::Impl {
 public:
  std::unique_ptr<LibyuvTransformPlan> plan;
};

LibyuvFrameTransformer::LibyuvFrameTransformer()
    : impl_(std::make_unique<Impl>()) {}

LibyuvFrameTransformer::~LibyuvFrameTransformer() = default;

bool LibyuvFrameTransformer::TransformNv21ToNv12(
    const uint8_t* sourceLuma,
    const uint8_t* sourceChroma,
    uint8_t* destination,
    const VideoFrameTransformGeometry& geometry,
    VideoFrameConversionTiming* timing) {
  if (timing != nullptr) {
    *timing = {};
  }
  if (sourceLuma == nullptr || sourceChroma == nullptr ||
      destination == nullptr || geometry.sourceWidth < 2 ||
      geometry.sourceHeight < 2 || geometry.targetWidth < 2 ||
      geometry.targetHeight < 2) {
    return false;
  }

  if (impl_->plan == nullptr ||
      !MatchesGeometry(impl_->plan->geometry, geometry)) {
    impl_->plan = std::make_unique<LibyuvTransformPlan>(geometry);
  }

  const auto splitStartedAt = std::chrono::steady_clock::now();
  SplitSourceChroma(sourceChroma, impl_->plan.get());
  const auto scaleStartedAt = std::chrono::steady_clock::now();
  if (!ScaleFrame(sourceLuma, destination, impl_->plan.get())) {
    return false;
  }
  const auto rotationStartedAt = std::chrono::steady_clock::now();
  if (!RotateFrame(destination, impl_->plan.get())) {
    return false;
  }
  const auto mergeStartedAt = std::chrono::steady_clock::now();
  WriteNv12Chroma(destination, *impl_->plan);
  const auto finishedAt = std::chrono::steady_clock::now();
  if (timing != nullptr) {
    timing->uvSplitMilliseconds = std::chrono::duration<double, std::milli>(
        scaleStartedAt - splitStartedAt).count();
    timing->scaleMilliseconds = std::chrono::duration<double, std::milli>(
        rotationStartedAt - scaleStartedAt).count();
    timing->rotationMilliseconds = geometry.rotation == 0 ? 0.0 :
        std::chrono::duration<double, std::milli>(mergeStartedAt - rotationStartedAt).count();
    timing->uvMergeMilliseconds = std::chrono::duration<double, std::milli>(
        finishedAt - mergeStartedAt).count();
    timing->valid = true;
  }
  return true;
}
}  // namespace internal
}  // namespace xmax
