//
//  video_frame_geometry.h
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

#ifndef XMAX_VIDEO_FRAME_GEOMETRY_H
#define XMAX_VIDEO_FRAME_GEOMETRY_H

#include <cstdint>

#include "video_frame_converter.h"

namespace xmax {
namespace internal {
/**
 * 以源像素坐标描述需要保留的裁剪区域。
 */
struct VideoFrameCropGeometry {

  /** 源坐标系内的裁剪矩形 */
  double x;
  double y;
  double width;
  double height;
};

/**
 * 描述源帧布局、裁剪区域及目标方向和尺寸，供视频转换计划使用。
 */
struct VideoFrameTransformGeometry {

  /** 源图像尺寸与平面布局 */
  int32_t sourceWidth;
  int32_t sourceHeight;
  int32_t sourceStride;
  int32_t sourceChromaStride;

  /** 目标方向与尺寸 */
  int32_t rotation;
  int32_t targetWidth;
  int32_t targetHeight;

  /** 源图像裁剪区域 */
  VideoFrameCropGeometry sourceCrop;
};

/**
 * 按目标宽高比与旋转方向计算源裁剪矩形及转换几何参数。
 *
 * @param configuration 源图像布局、旋转角度和目标尺寸配置。
 * @returns 可供转换计划使用的源布局、裁剪和目标几何信息。
 */
VideoFrameTransformGeometry MakeVideoFrameTransformGeometry(
    const VideoFrameTransformConfiguration& configuration);
}  /** namespace internal */
}  /** namespace xmax */

#endif
