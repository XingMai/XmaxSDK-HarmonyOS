//
//  video_frame_converter.h
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

#ifndef XMAX_VIDEO_FRAME_CONVERTER_H
#define XMAX_VIDEO_FRAME_CONVERTER_H

#include <cstdint>
#include <memory>

namespace xmax {

/** The source NV21 layout and target NV12 dimensions and rotation. */
struct VideoFrameTransformConfiguration {

  // Source dimensions and plane strides

  /** The source frame width, in pixels. */
  int32_t sourceWidth;

  /** The source frame height, in pixels. */
  int32_t sourceHeight;

  /** The source luma row stride, in bytes. */
  int32_t sourceStride;

  /** The source chroma row stride, in bytes. */
  int32_t sourceChromaStride;

  // Target orientation and output dimensions

  /** The clockwise video rotation. */
  int32_t rotation;

  /** The target frame width, in pixels. */
  int32_t targetWidth;

  /** The target frame height, in pixels. */
  int32_t targetHeight;
};

/**
 * Reuses intermediate buffers to transform NV21 into NV12. Dimensions must be even and within 2 to
 * 32768.
 */
class VideoFrameTransformer {
public:
  /** Creates a reusable video frame converter. */
  VideoFrameTransformer();

  /** Releases the cached conversion plan and intermediate buffers. */
  ~VideoFrameTransformer();

  /** Prevents copying so one instance exclusively owns the intermediate buffers. */
  VideoFrameTransformer(const VideoFrameTransformer &) = delete;

  /** Prevents copying of intermediate buffers and native state. */
  VideoFrameTransformer &operator=(const VideoFrameTransformer &) = delete;

  /**
   * Validates and transforms NV21 into cropped, scaled, rotated NV12; invalid input or conversion
   * failure throws.
   *
   * @param sourceLuma The source Y plane address.
   * @param sourceChroma The source interleaved chroma plane address.
   * @param destination The caller-owned NV12 buffer with capacity for 1.5 times the target pixel count.
   * @param configuration The source layout, rotation, and target dimensions.
   */
  void TransformNv21ToNv12(const uint8_t *sourceLuma,
      const uint8_t *sourceChroma,
      uint8_t *destination,
      const VideoFrameTransformConfiguration &configuration);

private:
  /** Owns the cached video conversion plan. */
  class Impl;

  // Exclusive conversion cache ownership

  /** The exclusively owned conversion implementation. */
  std::unique_ptr<Impl> impl_;
};
} // namespace xmax

#endif
