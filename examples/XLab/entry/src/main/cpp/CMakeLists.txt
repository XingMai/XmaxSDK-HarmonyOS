cmake_minimum_required(VERSION 3.5.0)
project(xlab_recorder)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(xlab_recorder SHARED realtime_recorder.cpp recorder_module.cpp file_frame_source.cpp file_video_surface.cpp)
target_compile_options(xlab_recorder PRIVATE -O3 -Wall -Wextra)
target_link_libraries(xlab_recorder PUBLIC
    ace_napi.z
    hilog_ndk.z
    libnative_media_venc.so
    libnative_media_vdec.so
    libnative_media_acodec.so
    libnative_media_avmuxer.so
    libnative_media_avdemuxer.so
    libnative_media_avsource.so
    libnative_media_codecbase.so
    libnative_media_core.so
    libnative_buffer.so
    libnative_image.so
    libnative_window.so
    libvideo_processing.so)
