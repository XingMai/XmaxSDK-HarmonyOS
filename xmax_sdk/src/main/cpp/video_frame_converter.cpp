//
//  video_frame_converter.cpp
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
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
 * 比较缓存转换计划与输入配置，判断中间缓冲能否复用。
 *
 * @param left 缓存转换计划持有的几何配置。
 * @param right 当前帧请求使用的转换配置。
 * @returns 源布局、方向和目标尺寸均一致时返回 true。
 */
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

/**
 * 将数值向下取整为偶数。
 *
 * @param value 待读取或计算的数值。
 * @returns 不大于原值的最大偶数。
 */
int32_t FloorToEven(double value) {
  return static_cast<int32_t>(std::floor(value)) & ~1;
}

/**
 * 将像素长度限制为合法偶数且不超过指定上限。
 *
 * @param value 待读取或计算的数值。
 * @param maximum 需要限制到的像素上限。
 * @returns 至少为 2 且不超过上限的偶数长度。
 */
int32_t ClampEvenLength(double value, int32_t maximum) {
  const int32_t evenMaximum = maximum & ~1;
  return std::clamp(FloorToEven(value), 2, evenMaximum);
}

/**
 * 将裁剪偏移限制为非负偶数且不超过指定边界。
 *
 * @param value 待读取或计算的数值。
 * @param maximum 需要限制到的像素上限。
 * @returns 合法的偶数裁剪偏移。
 */
int32_t ClampEvenOffset(
    double value,
    int32_t maximum) {
  return std::clamp(FloorToEven(value), 0, maximum & ~1);
}

/**
 * 将角度转换为 libyuv 使用的旋转模式。
 *
 * @param rotation 旋转角度，支持 0、90、180 或 270。
 * @returns 对应角度的 libyuv 旋转枚举。
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

/**
 * 持有可复用的 I420 像素缓冲区，提供平面地址与行跨度。
 */
class I420Buffer {
 public:
  /**
   * 重新设置 I420 平面布局，并按需分配亮度和色度缓冲区。
   *
   * @param width 画面宽度，单位像素。
   * @param height 画面高度，单位像素。
   * @param allocateLuma 是否为亮度平面分配缓冲区；false 时仅分配色度平面。
   * @returns 无返回值。
   */
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

  /**
   * 读取 I420 图像宽度。
   *
   * @returns 图像宽度，单位像素。
   */
  int32_t width() const {
    return width_;
  }

  /**
   * 读取 I420 图像高度。
   *
   * @returns 图像高度，单位像素。
   */
  int32_t height() const {
    return height_;
  }

  /**
   * 读取 I420 色度平面的行跨度。
   *
   * @returns U、V 平面每行的字节跨度。
   */
  int32_t chromaStride() const {
    return chromaWidth_;
  }

  /**
   * 取得 I420 亮度平面地址。
   *
   * @returns 亮度平面首地址。
   */
  uint8_t* y() {
    return uOffset_ == 0 ? nullptr : data_.data();
  }

  /**
   * 取得 I420 U 色度平面地址。
   *
   * @returns U 平面首地址。
   */
  uint8_t* u() {
    return data_.data() + uOffset_;
  }

  /**
   * 取得 I420 U 色度平面地址。
   *
   * @returns U 平面首地址。
   */
  const uint8_t* u() const {
    return data_.data() + uOffset_;
  }

  /**
   * 取得 I420 V 色度平面地址。
   *
   * @returns V 平面首地址。
   */
  uint8_t* v() {
    return data_.data() + vOffset_;
  }

  /**
   * 取得 I420 V 色度平面地址。
   *
   * @returns V 平面首地址。
   */
  const uint8_t* v() const {
    return data_.data() + vOffset_;
  }

 private:

  /** 像素尺寸与色度平面布局 */
  int32_t width_ = 0;
  int32_t height_ = 0;
  int32_t chromaWidth_ = 0;
  int32_t chromaHeight_ = 0;
  size_t uOffset_ = 0;
  size_t vOffset_ = 0;

  /** 可复用像素缓冲区 */
  std::vector<uint8_t> data_;
};

/**
 * 缓存裁剪、缩放和旋转所需的几何信息与中间帧，减少逐帧内存分配。
 */
struct LibyuvTransformPlan {
  /**
   * 按帧几何信息创建可复用的裁剪、缩放和旋转缓冲区。
   *
   * @param frameGeometry 已经计算好的裁剪、方向和目标尺寸。
   * @returns 无返回值；完成实例初始化。
   */
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

  /**
   * 选择转换流程中最终持有目标方向像素的中间帧。
   *
   * @returns 最终缩放或旋转后的 I420 帧引用。
   */
  const I420Buffer& finalFrame() const {
    return geometry.rotation == 0 ? scaledFrame : rotatedFrame;
  }

  /** 转换几何与偶数裁剪区域 */
  xmax::internal::VideoFrameTransformGeometry geometry;
  int32_t cropX = 0;
  int32_t cropY = 0;
  int32_t cropWidth = 0;
  int32_t cropHeight = 0;

  /** 格式转换、缩放与旋转中间帧 */
  I420Buffer convertedFrame;
  I420Buffer scaledFrame;
  I420Buffer rotatedFrame;
};

/**
 * 将 NV21 交错色度分离到转换计划的 I420 U、V 平面。
 *
 * @param sourceChroma 源图像交错色度平面首地址。
 * @param plan 包含几何信息与可复用中间帧的转换计划。
 * @returns 无返回值。
 */
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

/**
 * 按转换计划缩放源亮度及色度到目标 I420 平面。
 *
 * @param sourceLuma 源图像 Y 亮度平面首地址。
 * @param destination 调用方提供的目标 NV12 缓冲区，容量须覆盖目标宽高的 1.5 倍。
 * @param plan 包含几何信息与可复用中间帧的转换计划。
 * @returns libyuv 缩放成功时返回 true。
 */
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

/**
 * 将缩放后的 I420 帧旋转到目标方向，零角度时直接复用。
 *
 * @param destination 调用方提供的目标 NV12 缓冲区，容量须覆盖目标宽高的 1.5 倍。
 * @param plan 包含几何信息与可复用中间帧的转换计划。
 * @returns 旋转成功或无需旋转时返回 true。
 */
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

/**
 * 将最终 I420 色度平面合并为目标 NV12 的交错 UV 平面。
 *
 * @param destination 调用方提供的目标 NV12 缓冲区，容量须覆盖目标宽高的 1.5 倍。
 * @param plan 包含几何信息与可复用中间帧的转换计划。
 * @returns 无返回值。
 */
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
}  /** namespace */

namespace xmax {
/**
 * 持有视频转换计划，隔离转换器的缓存实现。
 */
class VideoFrameTransformer::Impl {
 public:

  /** 可复用视频转换计划 */
  std::unique_ptr<LibyuvTransformPlan> plan;
};

/**
 * 创建可复用的视频帧转换器。
 *
 * @returns 无返回值；完成实例初始化。
 */
VideoFrameTransformer::VideoFrameTransformer()
    : impl_(std::make_unique<Impl>()) {}

/**
 * 停止媒体输出并释放实例持有的原生资源与缓存。
 *
 * @returns 无返回值。
 */
VideoFrameTransformer::~VideoFrameTransformer() = default;

/**
 * 校验源布局并完成 NV21 到 NV12 的裁剪、缩放和旋转；非法参数或转换失败时抛出异常。
 *
 * @param sourceLuma 源图像 Y 亮度平面首地址。
 * @param sourceChroma 源图像交错色度平面首地址。
 * @param destination 调用方提供的目标 NV12 缓冲区，容量须覆盖目标宽高的 1.5 倍。
 * @param configuration 源图像布局、旋转角度和目标尺寸配置。
 * @returns 无返回值。
 */
void VideoFrameTransformer::TransformNv21ToNv12(
    const uint8_t* sourceLuma,
    const uint8_t* sourceChroma,
    uint8_t* destination,
    const VideoFrameTransformConfiguration& configuration) {
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

  SplitSourceChroma(sourceChroma, impl_->plan.get());
  if (!ScaleFrame(sourceLuma, destination, impl_->plan.get())) {
    throw std::runtime_error("libyuv frame scaling failed");
  }
  if (!RotateFrame(destination, impl_->plan.get())) {
    throw std::runtime_error("libyuv frame rotation failed");
  }
  WriteNv12Chroma(destination, *impl_->plan);
}
}  /** namespace xmax */
