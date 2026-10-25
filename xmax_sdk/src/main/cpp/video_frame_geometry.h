//
//  video_frame_geometry.h
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

#ifndef XMAX_VIDEO_FRAME_GEOMETRY_H
#define XMAX_VIDEO_FRAME_GEOMETRY_H

#include <cstdint>

#include "video_frame_converter.h"

namespace xmax {
namespace internal {

/** A crop rectangle in source pixel coordinates. */
struct VideoFrameCropGeometry {

  // Crop rectangle in source coordinates

  /** The horizontal coordinate. */
  double x;

  /** The vertical coordinate. */
  double y;

  /** The image or frame width. */
  double width;

  /** The image or frame height. */
  double height;
};

/** The source layout, crop, rotation, and target dimensions for a conversion plan. */
struct VideoFrameTransformGeometry {

  // Source image dimensions and plane layout

  /** The source frame width, in pixels. */
  int32_t sourceWidth;

  /** The source frame height, in pixels. */
  int32_t sourceHeight;

  /** The source luma row stride, in bytes. */
  int32_t sourceStride;

  /** The source chroma row stride, in bytes. */
  int32_t sourceChromaStride;

  // Target orientation and dimensions

  /** The clockwise video rotation. */
  int32_t rotation;

  /** The target frame width, in pixels. */
  int32_t targetWidth;

  /** The target frame height, in pixels. */
  int32_t targetHeight;

  // Source crop bounds

  /** The retained crop rectangle in source pixels. */
  VideoFrameCropGeometry sourceCrop;
};

/**
 * Resolves the source crop and conversion geometry for the target aspect ratio and rotation.
 *
 * @param configuration The source layout, rotation, and target dimensions.
 * @return The source layout, crop, and target geometry for conversion.
 */
VideoFrameTransformGeometry MakeVideoFrameTransformGeometry(
    const VideoFrameTransformConfiguration &configuration);
} // namespace internal
} // namespace xmax

#endif
