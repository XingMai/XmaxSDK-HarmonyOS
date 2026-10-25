//
//  native_frame_receiver.cpp
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

#include "native_frame_receiver.h"

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <exception>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>

#include "multimedia/image_framework/image/image_native.h"
#include "multimedia/image_framework/image/image_receiver_native.h"
#include "native_buffer/native_buffer.h"
#include "video_frame_converter.h"

namespace {
constexpr int32_t kFrameBufferCapacity = 4;

/** A converted camera frame and error details for delivery to ArkTS. */
struct FramePacket {

  // Pixel data and frame layout

  /** The owned media bytes. */
  std::unique_ptr<uint8_t[]> data;

  /** The valid media data length, in bytes. */
  size_t dataLength = 0;

  /** The image or frame width. */
  int32_t width = 0;

  /** The image or frame height. */
  int32_t height = 0;

  // Frame time and error notification

  /** The frame timestamp, in microseconds. */
  int64_t timestampUs = 0;

  /** The media processing failure description, if any. */
  std::string error;
};

/** Camera output dimensions, rotation, and frame-rate constraints. */
struct OutputConfiguration {

  // Target dimensions and rotation

  /** The image or frame width. */
  int32_t width = 0;

  /** The image or frame height. */
  int32_t height = 0;

  /** The clockwise video rotation. */
  int32_t rotation = 0;

  // Output and capture frame rates

  /** The video frame rate, in fps. */
  int32_t frameRate = 0;

  /** The camera capture frame rate, in fps. */
  int32_t captureFrameRate = 0;

  /**
   * Checks whether camera output dimensions, rotation, and frame rates are valid.
   *
   * @return True if the configuration supports native frame processing.
   */
  bool IsValid() const {
    const bool rotationSupported =
        rotation == 0 || rotation == 90 || rotation == 180 || rotation == 270;
    return width > 0 && height > 0 && width % 2 == 0 && height % 2 == 0 && rotationSupported &&
        frameRate > 0 && captureFrameRate > 0 && frameRate <= captureFrameRate;
  }
};

/** Receives CameraKit frames and converts them to NV12 on a worker for ArkTS delivery. */
class NativeFrameReceiver;

std::mutex receiverRegistryMutex;
std::unordered_map<OH_ImageReceiverNative *, NativeFrameReceiver *> receiverRegistry;

/** Receives CameraKit frames and converts them to NV12 on a worker for ArkTS delivery. */
class NativeFrameReceiver {
public:
  /** Creates a raw camera frame receiver. */
  NativeFrameReceiver() = default;

  /** Stops media output and releases owned native resources and caches. */
  ~NativeFrameReceiver() {
    Stop();
  }

  /**
   * Creates native media resources for the requested output format.
   *
   * @param env The current ArkTS N-API environment.
   * @param listener The ArkTS receiver for frames, end notifications, and errors.
   * @param sourceWidth The source image width, in pixels.
   * @param sourceHeight The source image height, in pixels.
   * @param error Receives the failure description.
   * @return True on successful initialization; false with an error description otherwise.
   */
  bool Initialize(napi_env env,
      napi_value listener,
      int32_t sourceWidth,
      int32_t sourceHeight,
      std::string *error) {
    OH_ImageReceiverOptions *options = nullptr;
    if (OH_ImageReceiverOptions_Create(&options) != IMAGE_SUCCESS || options == nullptr) {
      *error = "创建 Native 相机帧接收配置失败";
      return false;
    }

    const Image_Size sourceSize{static_cast<uint32_t>(sourceWidth),
        static_cast<uint32_t>(sourceHeight)};
    const bool optionsConfigured =
        OH_ImageReceiverOptions_SetSize(options, sourceSize) == IMAGE_SUCCESS &&
        OH_ImageReceiverOptions_SetCapacity(options, kFrameBufferCapacity) == IMAGE_SUCCESS;
    if (!optionsConfigured || OH_ImageReceiverNative_Create(options, &receiver_) != IMAGE_SUCCESS ||
        receiver_ == nullptr) {
      OH_ImageReceiverOptions_Release(options);
      *error = "创建 Native 相机帧接收器失败";
      return false;
    }
    OH_ImageReceiverOptions_Release(options);

    uint64_t surfaceId = 0;
    if (OH_ImageReceiverNative_GetReceivingSurfaceId(receiver_, &surfaceId) != IMAGE_SUCCESS) {
      *error = "获取 Native 相机帧表面标识失败";
      Stop();
      return false;
    }
    surfaceId_ = std::to_string(surfaceId);

    napi_value resourceName = nullptr;
    if (napi_create_string_utf8(env, "XmaxNativeFrameReceiver", NAPI_AUTO_LENGTH, &resourceName) !=
            napi_ok ||
        napi_create_threadsafe_function(env,
            listener,
            nullptr,
            resourceName,
            1,
            1,
            nullptr,
            nullptr,
            nullptr,
            CallListener,
            &listener_) != napi_ok) {
      *error = "创建 Native 相机帧回调失败";
      Stop();
      return false;
    }

    {
      std::lock_guard<std::mutex> lock(receiverRegistryMutex);
      receiverRegistry[receiver_] = this;
    }
    running_.store(true);
    if (OH_ImageReceiverNative_On(receiver_, OnFrameAvailable) != IMAGE_SUCCESS) {
      *error = "监听 Native 相机帧失败";
      Stop();
      return false;
    }
    listenerRegistered_ = true;

    worker_ = std::thread(&NativeFrameReceiver::Run, this);
    return true;
  }

  /**
   * Returns the receiving Surface identifier for CameraKit binding.
   *
   * @return The native receiving Surface identifier.
   */
  const std::string &SurfaceId() const {
    return surfaceId_;
  }

  /**
   * Validates and updates camera output dimensions, orientation, and sampling rate.
   *
   * @param width The frame width, in pixels.
   * @param height The frame height, in pixels.
   * @param rotation The rotation, in degrees: 0, 90, 180, or 270.
   * @param frameRate The target output frame rate, in fps.
   * @param captureFrameRate The camera capture frame rate, in fps.
   * @return True if the valid configuration was saved; false otherwise.
   */
  bool Configure(int32_t width,
      int32_t height,
      int32_t rotation,
      int32_t frameRate,
      int32_t captureFrameRate) {
    const OutputConfiguration configuration{width, height, rotation, frameRate, captureFrameRate};
    if (!configuration.IsValid()) {
      return false;
    }

    std::lock_guard<std::mutex> lock(configurationMutex_);
    configuration_ = configuration;
    return true;
  }

  /** Stops output and workers, then releases the file, media resources, and callback references. */
  void Stop() {
    const bool wasRunning = running_.exchange(false);
    if (receiver_ != nullptr && listenerRegistered_) {
      OH_ImageReceiverNative_Off(receiver_);
      listenerRegistered_ = false;
    }
    if (receiver_ != nullptr) {
      std::lock_guard<std::mutex> lock(receiverRegistryMutex);
      receiverRegistry.erase(receiver_);
    }

    if (wasRunning) {
      frameCondition_.notify_all();
      if (worker_.joinable()) {
        worker_.join();
      }
    }

    if (listener_ != nullptr) {
      napi_release_threadsafe_function(listener_, napi_tsfn_abort);
      listener_ = nullptr;
    }
    if (receiver_ != nullptr) {
      OH_ImageReceiverNative_Release(receiver_);
      receiver_ = nullptr;
    }
    surfaceId_.clear();
  }

private:
  /**
   * Wakes the receiver worker when the system reports an image.
   *
   * @param receiver The system receiver reporting an available frame.
   */
  static void OnFrameAvailable(OH_ImageReceiverNative *receiver) {
    NativeFrameReceiver *frameReceiver = nullptr;
    {
      std::lock_guard<std::mutex> lock(receiverRegistryMutex);
      const auto iterator = receiverRegistry.find(receiver);
      if (iterator != receiverRegistry.end()) {
        frameReceiver = iterator->second;
      }
    }
    if (frameReceiver == nullptr || !frameReceiver->running_.load()) {
      return;
    }

    frameReceiver->frameAvailable_.store(true);
    frameReceiver->frameCondition_.notify_one();
  }

  /**
   * Delivers media or status on the ArkTS thread and transfers or releases packet ownership.
   *
   * @param env The current ArkTS N-API environment.
   * @param callback The function to invoke on the ArkTS thread.
   * @param data The associated packet or asynchronous work context.
   */
  static void CallListener(napi_env env, napi_value callback, void *, void *data) {
    auto *packet = static_cast<FramePacket *>(data);
    if (packet == nullptr) {
      return;
    }
    if (env == nullptr || callback == nullptr) {
      delete packet;
      return;
    }

    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    napi_value arguments[5];
    for (auto &argument : arguments) {
      argument = undefined;
    }

    const bool hasError = !packet->error.empty();
    if (!hasError) {
      if (napi_create_external_arraybuffer(env,
              packet->data.get(),
              packet->dataLength,
              FinalizeFramePacket,
              packet,
              &arguments[0]) != napi_ok ||
          arguments[0] == nullptr) {
        delete packet;
        return;
      }
    }

    napi_create_int32(env, packet->width, &arguments[1]);
    napi_create_int32(env, packet->height, &arguments[2]);
    napi_create_double(env, static_cast<double>(packet->timestampUs), &arguments[3]);
    if (hasError) {
      napi_create_string_utf8(env, packet->error.c_str(), NAPI_AUTO_LENGTH, &arguments[4]);
    }

    napi_value result = nullptr;
    napi_call_function(env,
        undefined,
        callback,
        sizeof(arguments) / sizeof(arguments[0]),
        arguments,
        &result);
    if (hasError) {
      delete packet;
    }
  }

  /**
   * Releases a native frame packet when ArkTS releases its external buffer.
   *
   * @param hint The packet associated with the external frame buffer.
   */
  static void FinalizeFramePacket(napi_env, void *, void *hint) {
    delete static_cast<FramePacket *>(hint);
  }

  /** Waits for frames on the receiver worker and uses the latest output configuration. */
  void Run() {
    while (running_.load()) {
      std::unique_lock<std::mutex> lock(frameMutex_);
      frameCondition_.wait(lock, [this] { return !running_.load() || frameAvailable_.load(); });
      if (!running_.load()) {
        return;
      }
      frameAvailable_.store(false);
      lock.unlock();

      ProcessFrame();
    }
  }

  /** Acquires the latest camera image and applies output frame-rate sampling. */
  void ProcessFrame() {
    OutputConfiguration outputConfiguration;
    {
      std::lock_guard<std::mutex> lock(configurationMutex_);
      outputConfiguration = configuration_;
    }

    OH_ImageNative *image = nullptr;
    if (OH_ImageReceiverNative_ReadLatestImage(receiver_, &image) != IMAGE_SUCCESS ||
        image == nullptr) {
      // A failed read does not imply the camera stream has failed.
      // Drop this frame and wait for the next notification.
      return;
    }

    if (!ShouldProcessFrame(outputConfiguration)) {
      if (OH_ImageNative_Release(image) != IMAGE_SUCCESS) {
        ReportError("释放 Native 相机帧失败");
      }
      return;
    }

    try {
      ProcessImage(image, outputConfiguration);
    } catch (const std::exception &error) {
      ReportError(std::string("处理 Native 相机帧失败：") + error.what());
    } catch (...) {
      ReportError("处理 Native 相机帧失败：未知错误");
    }
    if (OH_ImageNative_Release(image) != IMAGE_SUCCESS) {
      ReportError("释放 Native 相机帧失败");
    }
  }

  /**
   * Maps the camera image layout for pixel conversion.
   *
   * @param image The acquired raw camera image.
   * @param outputConfiguration The target dimensions, rotation, and sampling-rate snapshot.
   */
  void ProcessImage(OH_ImageNative *image, const OutputConfiguration &outputConfiguration) {
    if (!outputConfiguration.IsValid()) {
      return;
    }

    Image_Size sourceSize{};
    if (OH_ImageNative_GetImageSize(image, &sourceSize) != IMAGE_SUCCESS || sourceSize.width <= 0 ||
        sourceSize.height <= 0 || sourceSize.width % 2 != 0 || sourceSize.height % 2 != 0) {
      ReportError("Native 相机帧尺寸无效");
      return;
    }

    const uint32_t componentType = ResolveComponentType(image);
    if (componentType == 0) {
      return;
    }
    OH_NativeBuffer *nativeBuffer = nullptr;
    size_t bufferSize = 0;
    int32_t rowStride = 0;
    int64_t timestamp = 0;
    if (OH_ImageNative_GetByteBuffer(image, componentType, &nativeBuffer) != IMAGE_SUCCESS ||
        nativeBuffer == nullptr ||
        OH_ImageNative_GetBufferSize(image, componentType, &bufferSize) != IMAGE_SUCCESS ||
        OH_ImageNative_GetRowStride(image, componentType, &rowStride) != IMAGE_SUCCESS ||
        rowStride <= 0 || static_cast<uint32_t>(rowStride) < sourceSize.width) {
      ReportError("访问 Native 相机帧缓冲区失败");
      return;
    }
    OH_ImageNative_GetTimestamp(image, &timestamp);

    void *mappedAddress = nullptr;
    if (OH_NativeBuffer_Map(nativeBuffer, &mappedAddress) != 0 || mappedAddress == nullptr) {
      ReportError("映射 Native 相机帧失败");
      return;
    }

    try {
      ProcessMappedBuffer(static_cast<const uint8_t *>(mappedAddress),
          bufferSize,
          sourceSize,
          rowStride,
          timestamp,
          outputConfiguration);
    } catch (...) {
      OH_NativeBuffer_Unmap(nativeBuffer);
      throw;
    }
    OH_NativeBuffer_Unmap(nativeBuffer);
  }

  /**
   * Validates a mapped image, converts it to target NV12, and queues delivery.
   *
   * @param address The mapped image buffer address.
   * @param bufferSize The mapped buffer length, in bytes.
   * @param sourceSize The source image dimensions.
   * @param rowStride The source image row stride, in bytes.
   * @param timestamp The source image timestamp, in nanoseconds.
   * @param outputConfiguration The target dimensions, rotation, and sampling-rate snapshot.
   */
  void ProcessMappedBuffer(const uint8_t *address,
      size_t bufferSize,
      const Image_Size &sourceSize,
      int32_t rowStride,
      int64_t timestamp,
      const OutputConfiguration &outputConfiguration) {
    const size_t sourceLumaLength =
        static_cast<size_t>(rowStride) * static_cast<size_t>(sourceSize.height);
    const size_t requiredLength = sourceLumaLength + sourceLumaLength / 2;
    if (bufferSize < requiredLength) {
      ReportError("Native 相机帧数据不完整");
      return;
    }

    const size_t targetLumaLength = static_cast<size_t>(outputConfiguration.width) *
        static_cast<size_t>(outputConfiguration.height);
    auto packet = std::make_unique<FramePacket>();
    packet->dataLength = targetLumaLength + targetLumaLength / 2;
    // The converter writes every output byte; avoid a redundant zero fill.
    // Each delivery owns its storage until the external ArrayBuffer is finalized.
    packet->data.reset(new uint8_t[packet->dataLength]);
    packet->width = outputConfiguration.width;
    packet->height = outputConfiguration.height;
    packet->timestampUs = timestamp > 0 ? timestamp / 1000
                                        : std::chrono::duration_cast<std::chrono::microseconds>(
                                              std::chrono::steady_clock::now().time_since_epoch())
                                              .count();

    const xmax::VideoFrameTransformConfiguration configuration{
        static_cast<int32_t>(sourceSize.width),
        static_cast<int32_t>(sourceSize.height),
        rowStride,
        rowStride,
        outputConfiguration.rotation,
        outputConfiguration.width,
        outputConfiguration.height};
    transformer_.TransformNv21ToNv12(address,
        address + sourceLumaLength,
        packet->data.get(),
        configuration);

    Dispatch(packet.release());
  }

  /**
   * Accumulates capture and target rates to decide whether to output a frame.
   *
   * @param outputConfiguration The target dimensions, rotation, and sampling-rate snapshot.
   * @return True if the current frame should be converted and delivered.
   */
  bool ShouldProcessFrame(const OutputConfiguration &outputConfiguration) {
    samplingAccumulator_ += outputConfiguration.frameRate;
    if (samplingAccumulator_ < outputConfiguration.captureFrameRate) {
      return false;
    }

    samplingAccumulator_ -= outputConfiguration.captureFrameRate;
    return true;
  }

  /**
   * Queries supported camera image component types.
   *
   * @param image The acquired raw camera image.
   * @return A readable component type, or zero with an error notification if querying fails.
   */
  uint32_t ResolveComponentType(OH_ImageNative *image) {
    if (componentType_ != 0) {
      return componentType_;
    }

    size_t componentCount = 0;
    if (OH_ImageNative_GetComponentTypes(image, nullptr, &componentCount) != IMAGE_SUCCESS ||
        componentCount == 0) {
      ReportError("获取 Native 相机帧分量失败");
      return 0;
    }

    const std::unique_ptr<uint32_t[]> componentTypes(new uint32_t[componentCount]);
    uint32_t *componentData = componentTypes.get();
    if (OH_ImageNative_GetComponentTypes(image, &componentData, &componentCount) != IMAGE_SUCCESS ||
        componentData == nullptr || componentCount == 0) {
      ReportError("读取 Native 相机帧分量失败");
      return 0;
    }

    componentType_ = componentData[0];
    return componentType_;
  }

  /**
   * Delivers a camera processing error to ArkTS as an error packet.
   *
   * @param message The failure description to deliver or log.
   */
  void ReportError(const std::string &message) {
    auto *packet = new FramePacket();
    packet->error = message;
    Dispatch(packet);
  }

  /**
   * Queues a packet for ArkTS delivery, releasing it if submission fails.
   *
   * @param packet The packet to consume, deliver, or release.
   */
  void Dispatch(FramePacket *packet) {
    if (listener_ == nullptr ||
        napi_call_threadsafe_function(listener_, packet, napi_tsfn_nonblocking) != napi_ok) {
      delete packet;
    }
  }

  // System receiver resources and ArkTS callback

  /** The native camera frame receiver. */
  OH_ImageReceiverNative *receiver_ = nullptr;

  /** The currently installed event handler. */
  napi_threadsafe_function listener_ = nullptr;

  /** The receiving Surface identifier bound to platform capture. */
  std::string surfaceId_;

  /** Whether the system frame-availability listener is registered. */
  bool listenerRegistered_ = false;

  // Worker and frame-availability synchronization
  std::atomic<bool> running_{false};
  std::atomic<bool> frameAvailable_{false};

  /** The worker consuming and converting incoming media frames. */
  std::thread worker_;

  /** The lock protecting frame availability notifications. */
  std::mutex frameMutex_;

  /** The condition waking the worker when a frame is available. */
  std::condition_variable frameCondition_;

  // Output configuration synchronization

  /** The lock protecting camera output configuration. */
  std::mutex configurationMutex_;

  /** The configuration for the current operation. */
  OutputConfiguration configuration_;

  // Frame sampling and pixel conversion caches

  /** The accumulated frame-rate sampling progress. */
  int32_t samplingAccumulator_ = 0;

  /** The image component type used to read native pixels. */
  uint32_t componentType_ = 0;

  /** The reusable pixel conversion plan and intermediate buffers. */
  xmax::VideoFrameTransformer transformer_;
};

/**
 * Reads a 32-bit integer from an ArkTS value.
 *
 * @param env The current ArkTS N-API environment.
 * @param value The value to read or calculate.
 * @param output Receives the converted or extracted value.
 * @return True if the value can be converted to a 32-bit integer.
 */
bool ReadInt32(napi_env env, napi_value value, int32_t *output) {
  return napi_get_value_int32(env, value, output) == napi_ok;
}

/**
 * Extracts the native frame receiver and ArkTS arguments.
 *
 * @param env The current ArkTS N-API environment.
 * @param info The ArkTS invocation arguments and receiver.
 * @param argumentCount The argument capacity on input and actual argument count on output.
 * @param arguments Receives the ArkTS invocation arguments.
 * @return The native receiver, or a null pointer with an ArkTS exception on failure.
 */
NativeFrameReceiver *UnwrapReceiver(napi_env env,
    napi_callback_info info,
    size_t *argumentCount,
    napi_value *arguments) {
  napi_value thisValue = nullptr;
  if (napi_get_cb_info(env, info, argumentCount, arguments, &thisValue, nullptr) != napi_ok) {
    return nullptr;
  }

  NativeFrameReceiver *receiver = nullptr;
  if (napi_unwrap(env, thisValue, reinterpret_cast<void **>(&receiver)) != napi_ok) {
    return nullptr;
  }
  return receiver;
}

/**
 * Deletes the native receiver and releases capture resources when its ArkTS wrapper is collected.
 *
 * @param data The associated packet or asynchronous work context.
 */
void FinalizeReceiver(napi_env, void *data, void *) {
  delete static_cast<NativeFrameReceiver *>(data);
}

/**
 * Returns the native receiving Surface identifier to ArkTS.
 *
 * @param env The current ArkTS N-API environment.
 * @param info The ArkTS invocation arguments and receiver.
 * @return The Surface identifier string; invalid invocation produces an exception and an empty value.
 */
napi_value GetSurfaceId(napi_env env, napi_callback_info info) {
  size_t argumentCount = 0;
  NativeFrameReceiver *receiver = UnwrapReceiver(env, info, &argumentCount, nullptr);
  if (receiver == nullptr) {
    napi_throw_error(env, nullptr, "Native frame receiver is unavailable");
    return nullptr;
  }

  napi_value result = nullptr;
  napi_create_string_utf8(env, receiver->SurfaceId().c_str(), NAPI_AUTO_LENGTH, &result);
  return result;
}

/**
 * Updates the native receiver from ArkTS output-format arguments.
 *
 * @param env The current ArkTS N-API environment.
 * @param info The ArkTS invocation arguments and receiver.
 * @return ArkTS undefined; invalid arguments produce an exception.
 */
napi_value ConfigureReceiver(napi_env env, napi_callback_info info) {
  size_t argumentCount = 5;
  napi_value arguments[5] = {nullptr, nullptr, nullptr, nullptr, nullptr};
  NativeFrameReceiver *receiver = UnwrapReceiver(env, info, &argumentCount, arguments);
  int32_t width = 0;
  int32_t height = 0;
  int32_t rotation = 0;
  int32_t frameRate = 0;
  int32_t captureFrameRate = 0;
  if (receiver == nullptr || argumentCount != 5 || !ReadInt32(env, arguments[0], &width) ||
      !ReadInt32(env, arguments[1], &height) || !ReadInt32(env, arguments[2], &rotation) ||
      !ReadInt32(env, arguments[3], &frameRate) ||
      !ReadInt32(env, arguments[4], &captureFrameRate) ||
      !receiver->Configure(width, height, rotation, frameRate, captureFrameRate)) {
    napi_throw_range_error(env, nullptr, "Native frame output configuration is invalid");
    return nullptr;
  }

  napi_value result = nullptr;
  napi_get_undefined(env, &result);
  return result;
}

/**
 * Stops and releases the native receiver bound to the ArkTS object.
 *
 * @param env The current ArkTS N-API environment.
 * @param info The ArkTS invocation arguments and receiver.
 * @return ArkTS undefined。
 */
napi_value ReleaseReceiver(napi_env env, napi_callback_info info) {
  size_t argumentCount = 0;
  NativeFrameReceiver *receiver = UnwrapReceiver(env, info, &argumentCount, nullptr);
  if (receiver != nullptr) {
    receiver->Stop();
  }

  napi_value result = nullptr;
  napi_get_undefined(env, &result);
  return result;
}

/**
 * Creates a CameraKit-compatible native receiver from source dimensions and a listener.
 *
 * @param env The current ArkTS N-API environment.
 * @param info The ArkTS invocation arguments and receiver.
 * @return The ArkTS receiver wrapper; failures produce an exception.
 */
napi_value CreateFrameReceiver(napi_env env, napi_callback_info info) {
  size_t argumentCount = 3;
  napi_value arguments[3] = {nullptr, nullptr, nullptr};
  if (napi_get_cb_info(env, info, &argumentCount, arguments, nullptr, nullptr) != napi_ok ||
      argumentCount != 3) {
    napi_throw_type_error(env, nullptr, "Expected source width, source height and frame listener");
    return nullptr;
  }

  int32_t sourceWidth = 0;
  int32_t sourceHeight = 0;
  napi_valuetype listenerType = napi_undefined;
  if (!ReadInt32(env, arguments[0], &sourceWidth) || !ReadInt32(env, arguments[1], &sourceHeight) ||
      sourceWidth <= 0 || sourceHeight <= 0 || sourceWidth % 2 != 0 || sourceHeight % 2 != 0 ||
      napi_typeof(env, arguments[2], &listenerType) != napi_ok || listenerType != napi_function) {
    napi_throw_type_error(env, nullptr, "Native frame receiver arguments are invalid");
    return nullptr;
  }

  auto *receiver = new NativeFrameReceiver();
  std::string error;
  if (!receiver->Initialize(env, arguments[2], sourceWidth, sourceHeight, &error)) {
    delete receiver;
    napi_throw_error(env, nullptr, error.c_str());
    return nullptr;
  }

  napi_value result = nullptr;
  napi_create_object(env, &result);
  napi_property_descriptor descriptors[] = {
      {"getSurfaceId", nullptr, GetSurfaceId, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"configure", nullptr, ConfigureReceiver, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"release", nullptr, ReleaseReceiver, nullptr, nullptr, nullptr, napi_default, nullptr}};
  napi_define_properties(env, result, sizeof(descriptors) / sizeof(descriptors[0]), descriptors);
  napi_wrap(env, result, receiver, FinalizeReceiver, nullptr, nullptr);
  return result;
}
} // namespace

namespace xmax {

/**
 * Exports native camera frame receiver creation.
 *
 * @param env The current ArkTS N-API environment.
 * @param exports The module object receiving SDK native exports.
 */
void DefineNativeFrameReceiver(napi_env env, napi_value exports) {
  napi_property_descriptor descriptor = {"createFrameReceiver",
      nullptr,
      CreateFrameReceiver,
      nullptr,
      nullptr,
      nullptr,
      napi_default,
      nullptr};
  napi_define_properties(env, exports, 1, &descriptor);
}
} // namespace xmax
