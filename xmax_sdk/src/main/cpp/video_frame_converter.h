//
//  video_frame_converter.h
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

#ifndef XMAX_VIDEO_FRAME_CONVERTER_H
#define XMAX_VIDEO_FRAME_CONVERTER_H

#include <cstdint>
#include <memory>

namespace xmax {
/**
 * 描述 NV21 源图像布局及目标 NV12 尺寸和旋转方向。
 */
struct VideoFrameTransformConfiguration {

  /** 源图像尺寸与平面行跨度 */
  int32_t sourceWidth;
  int32_t sourceHeight;
  int32_t sourceStride;
  int32_t sourceChromaStride;

  /** 目标方向与输出尺寸 */
  int32_t rotation;
  int32_t targetWidth;
  int32_t targetHeight;
};

/**
 * 复用中间缓冲区完成 NV21 到 NV12 的裁剪、缩放和旋转；输入尺寸须为 2～32768 的偶数。
 */
class VideoFrameTransformer {
 public:
  /**
   * 创建可复用的视频帧转换器。
   *
   * @returns 无返回值；完成实例初始化。
   */
  VideoFrameTransformer();
  /**
   * 停止媒体输出并释放实例持有的原生资源与缓存。
   *
   * @returns 无返回值。
   */
  ~VideoFrameTransformer();

  /**
   * 禁止复制转换器，确保中间缓冲由单个实例独占。
   *
   * @returns 无返回值；完成实例初始化。
   */
  VideoFrameTransformer(const VideoFrameTransformer&) = delete;
  /**
   * 禁止复制转换器，确保中间缓冲和原生状态由单个实例持有。
   *
   * @returns 此操作已删除，不提供运行时返回值。
   */
  VideoFrameTransformer& operator=(const VideoFrameTransformer&) = delete;

  /**
   * 校验源布局并完成 NV21 到 NV12 的裁剪、缩放和旋转；非法参数或转换失败时抛出异常。
   *
   * @param sourceLuma 源图像 Y 亮度平面首地址。
   * @param sourceChroma 源图像交错色度平面首地址。
   * @param destination 调用方提供的目标 NV12 缓冲区，容量须覆盖目标宽高的 1.5 倍。
   * @param configuration 源图像布局、旋转角度和目标尺寸配置。
   * @returns 无返回值。
   */
  void TransformNv21ToNv12(
      const uint8_t* sourceLuma,
      const uint8_t* sourceChroma,
      uint8_t* destination,
      const VideoFrameTransformConfiguration& configuration);

 private:
  /**
   * 持有视频转换计划，隔离转换器的缓存实现。
   */
  class Impl;

  /** 转换缓存的独占所有权 */
  std::unique_ptr<Impl> impl_;
};
}  /** namespace xmax */

#endif
