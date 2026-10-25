//
//  video_frame_converter.cpp
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

#include "video_frame_converter.h"
#include "video_frame_geometry.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <stdexcept>
#include <vector>

#include "libyuv/planar_functions.h"
#include "libyuv/rotate.h"
#include "libyuv/scale.h"

namespace {

/**
 * Checks whether the cached conversion plan matches the input configuration.
 *
 * @param left The geometry stored in the cached plan.
 * @param right The requested frame conversion configuration.
 * @return True if source layout, rotation, and target dimensions match.
 */
bool MatchesConfiguration(const xmax::internal::VideoFrameTransformGeometry &left,
    const xmax::VideoFrameTransformConfiguration &right) {
  return left.sourceWidth == right.sourceWidth && left.sourceHeight == right.sourceHeight &&
      left.sourceStride == right.sourceStride &&
      left.sourceChromaStride == right.sourceChromaStride && left.rotation == right.rotation &&
      left.targetWidth == right.targetWidth && left.targetHeight == right.targetHeight;
}

/**
 * Rounds a value down to an even integer.
 *
 * @param value The value to read or calculate.
 * @return The greatest even integer not exceeding the input.
 */
int32_t FloorToEven(double value) {
  return static_cast<int32_t>(std::floor(value)) & ~1;
}

/**
 * Clamps a pixel length to a valid even value within the limit.
 *
 * @param value The value to read or calculate.
 * @param maximum The pixel limit.
 * @return An even length of at least 2 within the limit.
 */
int32_t ClampEvenLength(double value, int32_t maximum) {
  const int32_t evenMaximum = maximum & ~1;
  return std::clamp(FloorToEven(value), 2, evenMaximum);
}

/**
 * Clamps a crop offset to a nonnegative even value within bounds.
 *
 * @param value The value to read or calculate.
 * @param maximum The pixel limit.
 * @return The valid even crop offset.
 */
int32_t ClampEvenOffset(double value, int32_t maximum) {
  return std::clamp(FloorToEven(value), 0, maximum & ~1);
}

/**
 * Converts degrees into the libyuv rotation mode.
 *
 * @param rotation The rotation, in degrees: 0, 90, 180, or 270.
 * @return The libyuv rotation mode.
 */
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

/** A reusable I420 buffer with plane addresses and row strides. */
class I420Buffer {
public:
  /**
   * Resets I420 layout and allocates luma and chroma buffers as needed.
   *
   * @param width The frame width, in pixels.
   * @param height The frame height, in pixels.
   * @param allocateLuma Whether to allocate luma; false allocates only chroma.
   */
  void Reset(int32_t width, int32_t height, bool allocateLuma) {
    width_ = width;
    height_ = height;
    chromaWidth_ = (width + 1) / 2;
    chromaHeight_ = (height + 1) / 2;

    // Converted/rotated Y is read from the source or written directly to the
    // caller. Only allocate intermediate Y when a separate rotation is needed.
    const size_t lumaLength =
        allocateLuma ? static_cast<size_t>(width_) * static_cast<size_t>(height_) : 0;
    const size_t chromaLength =
        static_cast<size_t>(chromaWidth_) * static_cast<size_t>(chromaHeight_);
    data_.resize(lumaLength + chromaLength * 2);
    uOffset_ = lumaLength;
    vOffset_ = lumaLength + chromaLength;
  }

  /**
   * Returns the I420 image width.
   *
   * @return The image width, in pixels.
   */
  int32_t width() const {
    return width_;
  }

  /**
   * Returns the I420 image height.
   *
   * @return The image height, in pixels.
   */
  int32_t height() const {
    return height_;
  }

  /**
   * Returns the I420 chroma row stride.
   *
   * @return The U and V plane row stride, in bytes.
   */
  int32_t chromaStride() const {
    return chromaWidth_;
  }

  /**
   * Returns the I420 luma plane address.
   *
   * @return The luma plane address.
   */
  uint8_t *y() {
    return uOffset_ == 0 ? nullptr : data_.data();
  }

  /**
   * Returns the I420 U plane address.
   *
   * @return The U plane address.
   */
  uint8_t *u() {
    return data_.data() + uOffset_;
  }

  /**
   * Returns the I420 U plane address.
   *
   * @return The U plane address.
   */
  const uint8_t *u() const {
    return data_.data() + uOffset_;
  }

  /**
   * Returns the I420 V plane address.
   *
   * @return The V plane address.
   */
  uint8_t *v() {
    return data_.data() + vOffset_;
  }

  /**
   * Returns the I420 V plane address.
   *
   * @return The V plane address.
   */
  const uint8_t *v() const {
    return data_.data() + vOffset_;
  }

private:
  // Pixel dimensions and chroma layout

  /** The image or frame width. */
  int32_t width_ = 0;

  /** The image or frame height. */
  int32_t height_ = 0;

  /** The chroma plane width, in samples. */
  int32_t chromaWidth_ = 0;

  /** The chroma plane height, in samples. */
  int32_t chromaHeight_ = 0;

  /** The U plane starting byte offset. */
  size_t uOffset_ = 0;

  /** The V plane starting byte offset. */
  size_t vOffset_ = 0;

  // Reusable pixel buffers

  /** The owned media bytes. */
  std::vector<uint8_t> data_;
};

/** Caches geometry and intermediate frames for crop, scaling, and rotation. */
struct LibyuvTransformPlan {

  /**
   * Allocates reusable intermediate buffers for the frame geometry.
   *
   * @param frameGeometry The resolved crop, rotation, and target dimensions.
   */
  explicit LibyuvTransformPlan(const xmax::internal::VideoFrameTransformGeometry &frameGeometry)
      : geometry(frameGeometry) {
    cropWidth = ClampEvenLength(geometry.sourceCrop.width, geometry.sourceWidth);
    cropHeight = ClampEvenLength(geometry.sourceCrop.height, geometry.sourceHeight);
    cropX = ClampEvenOffset(geometry.sourceCrop.x, geometry.sourceWidth - cropWidth);
    cropY = ClampEvenOffset(geometry.sourceCrop.y, geometry.sourceHeight - cropHeight);

    const bool swapsDimensions = geometry.rotation == 90 || geometry.rotation == 270;
    const int32_t scaledWidth = swapsDimensions ? geometry.targetHeight : geometry.targetWidth;
    const int32_t scaledHeight = swapsDimensions ? geometry.targetWidth : geometry.targetHeight;

    convertedFrame.Reset(cropWidth, cropHeight, false);
    scaledFrame.Reset(scaledWidth, scaledHeight, geometry.rotation != 0);
    if (geometry.rotation != 0) {
      rotatedFrame.Reset(geometry.targetWidth, geometry.targetHeight, false);
    }
  }

  /**
   * Selects the intermediate frame holding the final oriented pixels.
   *
   * @return The scaled or rotated I420 frame.
   */
  const I420Buffer &finalFrame() const {
    return geometry.rotation == 0 ? scaledFrame : rotatedFrame;
  }

  // Conversion geometry and even crop bounds

  /** The resolved source crop, orientation, and output dimensions. */
  xmax::internal::VideoFrameTransformGeometry geometry;

  /** The source crop's horizontal offset, in pixels. */
  int32_t cropX = 0;

  /** The source crop's vertical offset, in pixels. */
  int32_t cropY = 0;

  /** The source crop width, in pixels. */
  int32_t cropWidth = 0;

  /** The source crop height, in pixels. */
  int32_t cropHeight = 0;

  // Conversion, scaling, and rotation intermediates

  /** The reusable I420 conversion output. */
  I420Buffer convertedFrame;

  /** The reusable I420 scaling output. */
  I420Buffer scaledFrame;

  /** The reusable I420 rotation output. */
  I420Buffer rotatedFrame;
};

/**
 * Splits NV21 chroma into the conversion plan's I420 U and V planes.
 *
 * @param sourceChroma The source interleaved chroma plane address.
 * @param plan The conversion geometry and reusable intermediate frames.
 */
void SplitSourceChroma(const uint8_t *sourceChroma, LibyuvTransformPlan *plan) {
  const uint8_t *croppedChroma = sourceChroma +
      static_cast<size_t>(plan->cropY / 2) *
          static_cast<size_t>(plan->geometry.sourceChromaStride) +
      static_cast<size_t>(plan->cropX);

  libyuv::SplitUVPlane(croppedChroma,
      plan->geometry.sourceChromaStride,
      plan->convertedFrame.v(),
      plan->convertedFrame.chromaStride(),
      plan->convertedFrame.u(),
      plan->convertedFrame.chromaStride(),
      plan->cropWidth / 2,
      plan->cropHeight / 2);
}

/**
 * Scales luma and chroma into the target I420 planes.
 *
 * @param sourceLuma The source Y plane address.
 * @param destination The caller-owned NV12 buffer with capacity for 1.5 times the target pixel count.
 * @param plan The conversion geometry and reusable intermediate frames.
 * @return True if libyuv scaling succeeds.
 */
bool ScaleFrame(const uint8_t *sourceLuma, uint8_t *destination, LibyuvTransformPlan *plan) {
  const uint8_t *croppedLuma = sourceLuma +
      static_cast<size_t>(plan->cropY) * static_cast<size_t>(plan->geometry.sourceStride) +
      static_cast<size_t>(plan->cropX);
  uint8_t *scaledLuma = plan->geometry.rotation == 0 ? destination : plan->scaledFrame.y();
  return libyuv::I420Scale(croppedLuma,
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

/**
 * Rotates the scaled I420 frame, reusing it for zero rotation.
 *
 * @param destination The caller-owned NV12 buffer with capacity for 1.5 times the target pixel count.
 * @param plan The conversion geometry and reusable intermediate frames.
 * @return True if rotation succeeds or is unnecessary.
 */
bool RotateFrame(uint8_t *destination, LibyuvTransformPlan *plan) {
  if (plan->geometry.rotation == 0) {
    return true;
  }

  return libyuv::I420Rotate(plan->scaledFrame.y(),
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

/**
 * Interleaves the final I420 chroma into target NV12 UV.
 *
 * @param destination The caller-owned NV12 buffer with capacity for 1.5 times the target pixel count.
 * @param plan The conversion geometry and reusable intermediate frames.
 */
void WriteNv12Chroma(uint8_t *destination, const LibyuvTransformPlan &plan) {
  const I420Buffer &frame = plan.finalFrame();
  uint8_t *destinationChroma = destination +
      static_cast<size_t>(plan.geometry.targetWidth) *
          static_cast<size_t>(plan.geometry.targetHeight);

  libyuv::MergeUVPlane(frame.u(),
      frame.chromaStride(),
      frame.v(),
      frame.chromaStride(),
      destinationChroma,
      plan.geometry.targetWidth,
      plan.geometry.targetWidth / 2,
      plan.geometry.targetHeight / 2);
}
} // namespace

namespace xmax {

/** Owns the cached video conversion plan. */
class VideoFrameTransformer::Impl {
public:
  // Reusable video conversion plan

  /** The cached geometry and intermediate conversion buffers. */
  std::unique_ptr<LibyuvTransformPlan> plan;
};

/** Creates a reusable video frame converter. */
VideoFrameTransformer::VideoFrameTransformer() : impl_(std::make_unique<Impl>()) {
}

/** Releases the cached conversion plan and intermediate buffers. */
VideoFrameTransformer::~VideoFrameTransformer() = default;

/**
 * Validates and transforms NV21 into cropped, scaled, rotated NV12; invalid input or conversion failure
 * throws.
 *
 * @param sourceLuma The source Y plane address.
 * @param sourceChroma The source interleaved chroma plane address.
 * @param destination The caller-owned NV12 buffer with capacity for 1.5 times the target pixel count.
 * @param configuration The source layout, rotation, and target dimensions.
 */
void VideoFrameTransformer::TransformNv21ToNv12(const uint8_t *sourceLuma,
    const uint8_t *sourceChroma,
    uint8_t *destination,
    const VideoFrameTransformConfiguration &configuration) {
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

  if (impl_->plan == nullptr || !MatchesConfiguration(impl_->plan->geometry, configuration)) {
    impl_->plan = std::make_unique<LibyuvTransformPlan>(
        internal::MakeVideoFrameTransformGeometry(configuration));
  }

  SplitSourceChroma(sourceChroma, impl_->plan.get());
  if (!ScaleFrame(sourceLuma, destination, impl_->plan.get())) {
    throw std::runtime_error("libyuv frame scaling failed");
  }
  if (!RotateFrame(destination, impl_->plan.get())) {
    throw std::runtime_error("libyuv frame rotation failed");
  }
  WriteNv12Chroma(destination, *impl_->plan);
}
} // namespace xmax
