set(LIBYUV_SOURCE_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/source)

set(LIBYUV_COMMON_SOURCES
    ${LIBYUV_SOURCE_DIRECTORY}/convert.cc
    ${LIBYUV_SOURCE_DIRECTORY}/convert_from_argb.cc
    ${LIBYUV_SOURCE_DIRECTORY}/cpu_id.cc
    ${LIBYUV_SOURCE_DIRECTORY}/planar_functions.cc
    ${LIBYUV_SOURCE_DIRECTORY}/rotate_any.cc
    ${LIBYUV_SOURCE_DIRECTORY}/rotate.cc
    ${LIBYUV_SOURCE_DIRECTORY}/rotate_common.cc
    ${LIBYUV_SOURCE_DIRECTORY}/row_any.cc
    ${LIBYUV_SOURCE_DIRECTORY}/row_common.cc
    ${LIBYUV_SOURCE_DIRECTORY}/scale_any.cc
    ${LIBYUV_SOURCE_DIRECTORY}/scale.cc
    ${LIBYUV_SOURCE_DIRECTORY}/scale_common.cc
    ${LIBYUV_SOURCE_DIRECTORY}/scale_uv.cc
    ${LIBYUV_SOURCE_DIRECTORY}/video_common.cc
)

add_library(xmax_libyuv_common OBJECT ${LIBYUV_COMMON_SOURCES})

target_include_directories(xmax_libyuv_common PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_compile_definitions(xmax_libyuv_common PRIVATE
    LIBYUV_DISABLE_SME
    LIBYUV_DISABLE_SVE
)

target_compile_options(xmax_libyuv_common PRIVATE
    -O3
)

set(LIBYUV_OBJECTS $<TARGET_OBJECTS:xmax_libyuv_common>)

if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64)$" OR
    CMAKE_OHOS_ARCH_ABI STREQUAL "arm64-v8a" OR
    OHOS_ARCH STREQUAL "arm64-v8a")
  add_library(xmax_libyuv_neon64 OBJECT
      ${LIBYUV_SOURCE_DIRECTORY}/rotate_neon64.cc
      ${LIBYUV_SOURCE_DIRECTORY}/row_neon64.cc
      ${LIBYUV_SOURCE_DIRECTORY}/scale_neon64.cc
  )

  target_include_directories(xmax_libyuv_neon64 PRIVATE
      ${CMAKE_CURRENT_SOURCE_DIR}/include
  )

  target_compile_definitions(xmax_libyuv_neon64 PRIVATE
      LIBYUV_DISABLE_SME
      LIBYUV_DISABLE_SVE
  )

  target_compile_options(xmax_libyuv_neon64 PRIVATE
      -O3
      -march=armv8.2-a+dotprod+i8mm
  )

  list(APPEND LIBYUV_OBJECTS $<TARGET_OBJECTS:xmax_libyuv_neon64>)
endif()

add_library(xmax_libyuv STATIC ${LIBYUV_OBJECTS})

target_include_directories(xmax_libyuv PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

set_target_properties(
    xmax_libyuv_common
    xmax_libyuv
    PROPERTIES POSITION_INDEPENDENT_CODE ON
)

if(TARGET xmax_libyuv_neon64)
  set_target_properties(
      xmax_libyuv_neon64
      PROPERTIES POSITION_INDEPENDENT_CODE ON
  )
endif()
