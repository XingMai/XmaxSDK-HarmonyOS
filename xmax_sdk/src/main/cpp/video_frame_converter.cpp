#include "video_frame_converter.h"
#include "video_frame_geometry.h"

#include <algorithm>
#include <cmath>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <stdexcept>
#include <vector>

#include "libyuv/cpu_id.h"
#include "libyuv/planar_functions.h"
#include "libyuv/rotate.h"
#include "libyuv/scale.h"

namespace {
bool MatchesConfiguration(
    const xmax::internal::VideoFrameTransformGeometry& left,
    const xmax::VideoFrameTransformConfiguration& right) {
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
class VideoFrameTransformer::Impl {
 public:
  std::unique_ptr<LibyuvTransformPlan> plan;
  VideoFrameConversionTiming timing;
  const char* backend = "uninitialized";
};

VideoFrameTransformer::VideoFrameTransformer()
    : impl_(std::make_unique<Impl>()) {}

VideoFrameTransformer::~VideoFrameTransformer() = default;

const char* VideoFrameTransformer::backend() const {
  return impl_->backend;
}

const VideoFrameConversionTiming& VideoFrameTransformer::timing() const {
  return impl_->timing;
}

void VideoFrameTransformer::TransformNv21ToNv12(
    const uint8_t* sourceLuma,
    const uint8_t* sourceChroma,
    uint8_t* destination,
    const VideoFrameTransformConfiguration& configuration) {
  impl_->timing = {};
  const auto validLength = [](int32_t length) {
    return length >= 2 && length <= 32768 && length % 2 == 0;
  };
  const int32_t rotation = configuration.rotation;
  if (sourceLuma == nullptr || sourceChroma == nullptr || destination == nullptr ||
      !validLength(configuration.sourceWidth) || !validLength(configuration.sourceHeight) ||
      !validLength(configuration.targetWidth) || !validLength(configuration.targetHeight) ||
      configuration.sourceStride < configuration.sourceWidth ||
      configuration.sourceChromaStride < configuration.sourceWidth ||
      (rotation != 0 && rotation != 90 && rotation != 180 && rotation != 270)) {
    throw std::invalid_argument("Invalid NV21 frame configuration");
  }

  if (impl_->plan == nullptr ||
      !MatchesConfiguration(impl_->plan->geometry, configuration)) {
    impl_->plan = std::make_unique<LibyuvTransformPlan>(
        internal::MakeVideoFrameTransformGeometry(configuration));
  }

  const auto splitStartedAt = std::chrono::steady_clock::now();
  SplitSourceChroma(sourceChroma, impl_->plan.get());
  const auto scaleStartedAt = std::chrono::steady_clock::now();
  if (!ScaleFrame(sourceLuma, destination, impl_->plan.get())) {
    throw std::runtime_error("libyuv frame scaling failed");
  }
  const auto rotationStartedAt = std::chrono::steady_clock::now();
  if (!RotateFrame(destination, impl_->plan.get())) {
    throw std::runtime_error("libyuv frame rotation failed");
  }
  const auto mergeStartedAt = std::chrono::steady_clock::now();
  WriteNv12Chroma(destination, *impl_->plan);
  const auto finishedAt = std::chrono::steady_clock::now();
  impl_->timing.uvSplitMilliseconds = std::chrono::duration<double, std::milli>(
      scaleStartedAt - splitStartedAt).count();
  impl_->timing.scaleMilliseconds = std::chrono::duration<double, std::milli>(
      rotationStartedAt - scaleStartedAt).count();
  impl_->timing.rotationMilliseconds = rotation == 0 ? 0.0 :
      std::chrono::duration<double, std::milli>(mergeStartedAt - rotationStartedAt).count();
  impl_->timing.uvMergeMilliseconds = std::chrono::duration<double, std::milli>(
      finishedAt - mergeStartedAt).count();
  impl_->timing.valid = true;
  // libyuv supplies its own C implementation when NEON is unavailable.
  impl_->backend = libyuv::TestCpuFlag(libyuv::kCpuHasNEON) ?
      "libyuv (NEON enabled)" : "libyuv (C)";
}
}  // namespace xmax
