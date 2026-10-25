//
//  external_video_converter.h
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

#ifndef XMAX_EXTERNAL_VIDEO_CONVERTER_H
#define XMAX_EXTERNAL_VIDEO_CONVERTER_H

#include <cstddef>
#include <cstdint>

namespace xmax {

/** A read-only visible plane with a byte length and padded row stride. */
struct ExternalVideoPlane {
  /** The source bytes, valid only during synchronous conversion. */
  const uint8_t *data;

  /** The accessible byte count from data. */
  size_t length;

  /** The row stride in bytes, including padding. */
  int32_t stride;
};

/**
 * Copies or scales upright NV12 or BGRA into caller-owned tightly packed NV12.
 *
 * @param first The source Y or BGRA plane.
 * @param second The interleaved UV plane, unused for BGRA.
 * @param bgra Whether the source is byte-ordered BGRA rather than video-range NV12.
 * @param width The declared source width.
 * @param height The declared source height.
 * @param outputWidth The resolved output width.
 * @param outputHeight The resolved output height.
 * @param output Destination storage of outputWidth * outputHeight * 3 / 2 bytes.
 */
void ConvertExternalVideo(ExternalVideoPlane first, ExternalVideoPlane second, bool bgra,
    int32_t width, int32_t height, int32_t outputWidth, int32_t outputHeight, uint8_t *output);
} // namespace xmax

#endif
