cmake_minimum_required(VERSION 3.5.0)
project(xmax_video)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(xmax_video SHARED
    audio_pcm_converter.cpp
    native_audio_file_decoder.cpp
    native_video_file_decoder.cpp
    xmax_video_module.cpp
)

target_compile_options(xmax_video PRIVATE
    -O3
)

target_link_libraries(xmax_video PUBLIC
    ace_napi.z
    hilog_ndk.z
    libnative_media_avdemuxer.so
    libnative_media_avsource.so
    libnative_media_acodec.so
    libnative_media_codecbase.so
    libnative_media_core.so
    libnative_media_vdec.so
)
