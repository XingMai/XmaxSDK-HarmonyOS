#ifndef XLAB_FILE_VIDEO_SURFACE_H
#define XLAB_FILE_VIDEO_SURFACE_H

#include <atomic>
#include <cstdint>
#include <functional>
#include <memory>

struct NativeWindow;

/** App-owned Surface output for decoding HDR Vivid into SDR NV12. */
class FileVideoSurface {
public:
  /** Receives mapped Y/UV pixels, byte strides, and actual dimensions, valid only during the callback. */
  using PixelConsumer = std::function<void(const uint8_t *, int, const uint8_t *, int, int, int)>;

  FileVideoSurface(int width, int height, const std::atomic<bool> &stopping);
  ~FileVideoSurface();

  NativeWindow *InputWindow() const;
  void Start();
  void CheckError();

  /** Reads one processed frame on the file worker; render and buffer release stay on that thread. */
  bool Read(const PixelConsumer &consume);

private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

#endif
