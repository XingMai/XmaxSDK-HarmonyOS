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
#include <time.h>
#include <unordered_map>
#include <vector>

#include "multimedia/image_framework/image/image_native.h"
#include "multimedia/image_framework/image/image_receiver_native.h"
#include "native_buffer/native_buffer.h"
#include "video_frame_converter.h"

namespace {
constexpr int32_t kFrameBufferCapacity = 4;

struct FramePacket {
  std::vector<uint8_t> data;
  int32_t width = 0;
  int32_t height = 0;
  int64_t timestampUs = 0;
  double processingMilliseconds = 0.0;
  int32_t droppedFrames = 0;
  int32_t skippedFrames = 0;
  std::string error;
  const char* conversionBackend = "unknown";
  double threadCpuMilliseconds = -1.0;
  double sampleTimeMilliseconds = 0.0;
};

struct OutputConfiguration {
  int32_t width = 0;
  int32_t height = 0;
  int32_t rotation = 0;
  int32_t frameRate = 0;
  int32_t captureFrameRate = 0;

  bool IsValid() const {
    const bool rotationSupported = rotation == 0 || rotation == 90 ||
        rotation == 180 || rotation == 270;
    return width > 0 && height > 0 && width % 2 == 0 &&
        height % 2 == 0 && rotationSupported && frameRate > 0 &&
        captureFrameRate > 0 && frameRate <= captureFrameRate;
  }
};

class NativeFrameReceiver;

std::mutex receiverRegistryMutex;
std::unordered_map<OH_ImageReceiverNative*, NativeFrameReceiver*>
    receiverRegistry;

class NativeFrameReceiver {
 public:
  NativeFrameReceiver() = default;

  ~NativeFrameReceiver() {
    Stop();
  }

  bool Initialize(
      napi_env env,
      napi_value listener,
      int32_t sourceWidth,
      int32_t sourceHeight,
      std::string* error) {
    OH_ImageReceiverOptions* options = nullptr;
    if (OH_ImageReceiverOptions_Create(&options) != IMAGE_SUCCESS ||
        options == nullptr) {
      *error = "创建 Native 相机帧接收配置失败";
      return false;
    }

    const Image_Size sourceSize{
        static_cast<uint32_t>(sourceWidth),
        static_cast<uint32_t>(sourceHeight)
    };
    const bool optionsConfigured =
        OH_ImageReceiverOptions_SetSize(options, sourceSize) == IMAGE_SUCCESS &&
        OH_ImageReceiverOptions_SetCapacity(
            options, kFrameBufferCapacity) == IMAGE_SUCCESS;
    if (!optionsConfigured ||
        OH_ImageReceiverNative_Create(options, &receiver_) != IMAGE_SUCCESS ||
        receiver_ == nullptr) {
      OH_ImageReceiverOptions_Release(options);
      *error = "创建 Native 相机帧接收器失败";
      return false;
    }
    OH_ImageReceiverOptions_Release(options);

    uint64_t surfaceId = 0;
    if (OH_ImageReceiverNative_GetReceivingSurfaceId(
        receiver_, &surfaceId) != IMAGE_SUCCESS) {
      *error = "获取 Native 相机帧表面标识失败";
      Stop();
      return false;
    }
    surfaceId_ = std::to_string(surfaceId);

    napi_value resourceName = nullptr;
    if (napi_create_string_utf8(
        env,
        "XmaxNativeFrameReceiver",
        NAPI_AUTO_LENGTH,
        &resourceName) != napi_ok ||
        napi_create_threadsafe_function(
            env,
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
    if (OH_ImageReceiverNative_On(
        receiver_, OnFrameAvailable) != IMAGE_SUCCESS) {
      *error = "监听 Native 相机帧失败";
      Stop();
      return false;
    }
    listenerRegistered_ = true;

    worker_ = std::thread(&NativeFrameReceiver::Run, this);
    return true;
  }

  const std::string& SurfaceId() const {
    return surfaceId_;
  }

  bool Configure(
      int32_t width,
      int32_t height,
      int32_t rotation,
      int32_t frameRate,
      int32_t captureFrameRate) {
    const OutputConfiguration configuration{
        width,
        height,
        rotation,
        frameRate,
        captureFrameRate
    };
    if (!configuration.IsValid()) {
      return false;
    }

    std::lock_guard<std::mutex> lock(configurationMutex_);
    configuration_ = configuration;
    return true;
  }

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
  static void OnFrameAvailable(OH_ImageReceiverNative* receiver) {
    NativeFrameReceiver* frameReceiver = nullptr;
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

    if (frameReceiver->frameAvailable_.exchange(true)) {
      frameReceiver->droppedFrameCount_.fetch_add(1);
    }
    frameReceiver->frameCondition_.notify_one();
  }

  static void CallListener(
      napi_env env,
      napi_value callback,
      void*,
      void* data) {
    auto* packet = static_cast<FramePacket*>(data);
    if (packet == nullptr) {
      return;
    }
    if (env == nullptr || callback == nullptr) {
      delete packet;
      return;
    }

    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    napi_value arguments[11];
    for (auto& argument : arguments) {
      argument = undefined;
    }

    const bool hasError = !packet->error.empty();
    if (!hasError) {
      if (napi_create_external_arraybuffer(
          env,
          packet->data.data(),
          packet->data.size(),
          FinalizeFramePacket,
          packet,
          &arguments[0]) != napi_ok || arguments[0] == nullptr) {
        delete packet;
        return;
      }
    }

    napi_create_int32(env, packet->width, &arguments[1]);
    napi_create_int32(env, packet->height, &arguments[2]);
    napi_create_double(
        env,
        static_cast<double>(packet->timestampUs),
        &arguments[3]);
    if (!hasError) {
      napi_create_double(
          env,
          packet->processingMilliseconds,
          &arguments[5]);
      napi_create_int32(
          env,
          packet->droppedFrames,
          &arguments[6]);
      napi_create_int32(
          env,
          packet->skippedFrames,
          &arguments[7]);
      napi_create_string_utf8(env, packet->conversionBackend, NAPI_AUTO_LENGTH, &arguments[8]);
      if (packet->threadCpuMilliseconds >= 0.0) {
        napi_create_double(env, packet->threadCpuMilliseconds, &arguments[9]);
      }
      napi_create_double(env, packet->sampleTimeMilliseconds, &arguments[10]);
    }
    if (hasError) {
      napi_create_string_utf8(
          env,
          packet->error.c_str(),
          NAPI_AUTO_LENGTH,
          &arguments[4]);
    }

    napi_value result = nullptr;
    napi_call_function(
        env,
        undefined,
        callback,
        sizeof(arguments) / sizeof(arguments[0]),
        arguments,
        &result);
    if (hasError) {
      delete packet;
    }
  }

  static void FinalizeFramePacket(
      napi_env,
      void*,
      void* hint) {
    delete static_cast<FramePacket*>(hint);
  }

  void Run() {
    while (running_.load()) {
      std::unique_lock<std::mutex> lock(frameMutex_);
      frameCondition_.wait(lock, [this] {
        return !running_.load() || frameAvailable_.load();
      });
      if (!running_.load()) {
        return;
      }
      frameAvailable_.store(false);
      lock.unlock();

      ProcessFrame();
    }
  }

  void ProcessFrame() {
    OutputConfiguration outputConfiguration;
    {
      std::lock_guard<std::mutex> lock(configurationMutex_);
      outputConfiguration = configuration_;
    }

    OH_ImageNative* image = nullptr;
    if (OH_ImageReceiverNative_ReadLatestImage(
        receiver_, &image) != IMAGE_SUCCESS || image == nullptr) {
      ReportError("获取 Native 相机帧失败");
      return;
    }

    if (!ShouldProcessFrame(outputConfiguration)) {
      skippedFrameCount_.fetch_add(1);
      if (OH_ImageNative_Release(image) != IMAGE_SUCCESS) {
        ReportError("释放 Native 相机帧失败");
      }
      return;
    }

    try {
      ProcessImage(image, outputConfiguration);
    } catch (const std::exception& error) {
      ReportError(std::string("处理 Native 相机帧失败：") + error.what());
    } catch (...) {
      ReportError("处理 Native 相机帧失败：未知错误");
    }
    if (OH_ImageNative_Release(image) != IMAGE_SUCCESS) {
      ReportError("释放 Native 相机帧失败");
    }
  }

  void ProcessImage(
      OH_ImageNative* image,
      const OutputConfiguration& outputConfiguration) {
    if (!outputConfiguration.IsValid()) {
      return;
    }

    Image_Size sourceSize{};
    if (OH_ImageNative_GetImageSize(image, &sourceSize) != IMAGE_SUCCESS ||
        sourceSize.width <= 0 || sourceSize.height <= 0 ||
        sourceSize.width % 2 != 0 || sourceSize.height % 2 != 0) {
      ReportError("Native 相机帧尺寸无效");
      return;
    }

    const uint32_t componentType = ResolveComponentType(image);
    if (componentType == 0) {
      return;
    }
    OH_NativeBuffer* nativeBuffer = nullptr;
    size_t bufferSize = 0;
    int32_t rowStride = 0;
    int64_t timestamp = 0;
    if (OH_ImageNative_GetByteBuffer(
        image, componentType, &nativeBuffer) != IMAGE_SUCCESS ||
        nativeBuffer == nullptr ||
        OH_ImageNative_GetBufferSize(
            image, componentType, &bufferSize) != IMAGE_SUCCESS ||
        OH_ImageNative_GetRowStride(
            image, componentType, &rowStride) != IMAGE_SUCCESS ||
        rowStride < sourceSize.width) {
      ReportError("访问 Native 相机帧缓冲区失败");
      return;
    }
    OH_ImageNative_GetTimestamp(image, &timestamp);

    void* mappedAddress = nullptr;
    if (OH_NativeBuffer_Map(
        nativeBuffer, &mappedAddress) != 0 ||
        mappedAddress == nullptr) {
      ReportError("映射 Native 相机帧失败");
      return;
    }

    try {
      ProcessMappedBuffer(
          static_cast<const uint8_t*>(mappedAddress),
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

  void ProcessMappedBuffer(
      const uint8_t* address,
      size_t bufferSize,
      const Image_Size& sourceSize,
      int32_t rowStride,
      int64_t timestamp,
      const OutputConfiguration& outputConfiguration) {
    const size_t sourceLumaLength = static_cast<size_t>(rowStride) *
        static_cast<size_t>(sourceSize.height);
    const size_t requiredLength = sourceLumaLength + sourceLumaLength / 2;
    if (bufferSize < requiredLength) {
      ReportError("Native 相机帧数据不完整");
      return;
    }

    const size_t targetLumaLength =
        static_cast<size_t>(outputConfiguration.width) *
        static_cast<size_t>(outputConfiguration.height);
    const auto processingStartedAt = std::chrono::steady_clock::now();
    auto* packet = new FramePacket();
    packet->width = outputConfiguration.width;
    packet->height = outputConfiguration.height;
    packet->timestampUs = timestamp > 0 ? timestamp / 1000 :
        std::chrono::duration_cast<std::chrono::microseconds>(
            std::chrono::steady_clock::now().time_since_epoch()).count();
    packet->data.resize(targetLumaLength + targetLumaLength / 2);

    const xmax::VideoFrameTransformConfiguration configuration{
        static_cast<int32_t>(sourceSize.width),
        static_cast<int32_t>(sourceSize.height),
        rowStride,
        rowStride,
        outputConfiguration.rotation,
        outputConfiguration.width,
        outputConfiguration.height
    };
    transformer_.TransformNv21ToNv12(
        address,
        address + sourceLumaLength,
        packet->data.data(),
        configuration);
    packet->processingMilliseconds =
        std::chrono::duration<double, std::milli>(
            std::chrono::steady_clock::now() - processingStartedAt).count();
    packet->conversionBackend = transformer_.backend();
    // Read on the capture worker, not on the ArkTS callback thread. Cumulative
    // samples include work spent on skipped/dropped frames between deliveries.
    timespec cpuTime{};
    if (clock_gettime(CLOCK_THREAD_CPUTIME_ID, &cpuTime) == 0) {
      packet->threadCpuMilliseconds = static_cast<double>(cpuTime.tv_sec) * 1000.0 +
          static_cast<double>(cpuTime.tv_nsec) / 1000000.0;
    }
    packet->sampleTimeMilliseconds = std::chrono::duration<double, std::milli>(
        std::chrono::steady_clock::now().time_since_epoch()).count();
    packet->droppedFrames = droppedFrameCount_.exchange(0);
    packet->skippedFrames = skippedFrameCount_.exchange(0);
    Dispatch(packet);
  }

  bool ShouldProcessFrame(
      const OutputConfiguration& outputConfiguration) {
    samplingAccumulator_ += outputConfiguration.frameRate;
    if (samplingAccumulator_ < outputConfiguration.captureFrameRate) {
      return false;
    }

    samplingAccumulator_ -= outputConfiguration.captureFrameRate;
    return true;
  }

  uint32_t ResolveComponentType(OH_ImageNative* image) {
    if (componentType_ != 0) {
      return componentType_;
    }

    size_t componentCount = 0;
    if (OH_ImageNative_GetComponentTypes(
        image, nullptr, &componentCount) != IMAGE_SUCCESS ||
        componentCount == 0) {
      ReportError("获取 Native 相机帧分量失败");
      return 0;
    }

    const std::unique_ptr<uint32_t[]> componentTypes(
        new uint32_t[componentCount]);
    uint32_t* componentData = componentTypes.get();
    if (OH_ImageNative_GetComponentTypes(
        image, &componentData, &componentCount) != IMAGE_SUCCESS ||
        componentData == nullptr || componentCount == 0) {
      ReportError("读取 Native 相机帧分量失败");
      return 0;
    }

    componentType_ = componentData[0];
    return componentType_;
  }

  void ReportError(const std::string& message) {
    auto* packet = new FramePacket();
    packet->error = message;
    Dispatch(packet);
  }

  void Dispatch(FramePacket* packet) {
    if (listener_ == nullptr || napi_call_threadsafe_function(
        listener_, packet, napi_tsfn_nonblocking) != napi_ok) {
      if (packet->error.empty() && !packet->data.empty()) {
        droppedFrameCount_.fetch_add(packet->droppedFrames + 1);
        skippedFrameCount_.fetch_add(packet->skippedFrames);
      }
      delete packet;
    }
  }

  OH_ImageReceiverNative* receiver_ = nullptr;
  napi_threadsafe_function listener_ = nullptr;
  std::string surfaceId_;
  bool listenerRegistered_ = false;

  std::atomic<bool> running_{false};
  std::atomic<bool> frameAvailable_{false};
  std::atomic<int32_t> droppedFrameCount_{0};
  std::atomic<int32_t> skippedFrameCount_{0};
  std::thread worker_;
  std::mutex frameMutex_;
  std::condition_variable frameCondition_;

  std::mutex configurationMutex_;
  OutputConfiguration configuration_;
  int32_t samplingAccumulator_ = 0;

  uint32_t componentType_ = 0;
  xmax::VideoFrameTransformer transformer_;
};

bool ReadInt32(
    napi_env env,
    napi_value value,
    int32_t* output) {
  return napi_get_value_int32(env, value, output) == napi_ok;
}

NativeFrameReceiver* UnwrapReceiver(
    napi_env env,
    napi_callback_info info,
    size_t* argumentCount,
    napi_value* arguments) {
  napi_value thisValue = nullptr;
  if (napi_get_cb_info(
      env,
      info,
      argumentCount,
      arguments,
      &thisValue,
      nullptr) != napi_ok) {
    return nullptr;
  }

  NativeFrameReceiver* receiver = nullptr;
  if (napi_unwrap(
      env,
      thisValue,
      reinterpret_cast<void**>(&receiver)) != napi_ok) {
    return nullptr;
  }
  return receiver;
}

void FinalizeReceiver(
    napi_env,
    void* data,
    void*) {
  delete static_cast<NativeFrameReceiver*>(data);
}

napi_value GetSurfaceId(
    napi_env env,
    napi_callback_info info) {
  size_t argumentCount = 0;
  NativeFrameReceiver* receiver = UnwrapReceiver(
      env, info, &argumentCount, nullptr);
  if (receiver == nullptr) {
    napi_throw_error(env, nullptr, "Native frame receiver is unavailable");
    return nullptr;
  }

  napi_value result = nullptr;
  napi_create_string_utf8(
      env,
      receiver->SurfaceId().c_str(),
      NAPI_AUTO_LENGTH,
      &result);
  return result;
}

napi_value ConfigureReceiver(
    napi_env env,
    napi_callback_info info) {
  size_t argumentCount = 5;
  napi_value arguments[5] = {nullptr, nullptr, nullptr, nullptr, nullptr};
  NativeFrameReceiver* receiver = UnwrapReceiver(
      env, info, &argumentCount, arguments);
  int32_t width = 0;
  int32_t height = 0;
  int32_t rotation = 0;
  int32_t frameRate = 0;
  int32_t captureFrameRate = 0;
  if (receiver == nullptr || argumentCount != 5 ||
      !ReadInt32(env, arguments[0], &width) ||
      !ReadInt32(env, arguments[1], &height) ||
      !ReadInt32(env, arguments[2], &rotation) ||
      !ReadInt32(env, arguments[3], &frameRate) ||
      !ReadInt32(env, arguments[4], &captureFrameRate) ||
      !receiver->Configure(
          width,
          height,
          rotation,
          frameRate,
          captureFrameRate)) {
    napi_throw_range_error(env, nullptr, "Native frame output configuration is invalid");
    return nullptr;
  }

  napi_value result = nullptr;
  napi_get_undefined(env, &result);
  return result;
}

napi_value ReleaseReceiver(
    napi_env env,
    napi_callback_info info) {
  size_t argumentCount = 0;
  NativeFrameReceiver* receiver = UnwrapReceiver(
      env, info, &argumentCount, nullptr);
  if (receiver != nullptr) {
    receiver->Stop();
  }

  napi_value result = nullptr;
  napi_get_undefined(env, &result);
  return result;
}

napi_value CreateFrameReceiver(
    napi_env env,
    napi_callback_info info) {
  size_t argumentCount = 3;
  napi_value arguments[3] = {nullptr, nullptr, nullptr};
  if (napi_get_cb_info(
      env,
      info,
      &argumentCount,
      arguments,
      nullptr,
      nullptr) != napi_ok || argumentCount != 3) {
    napi_throw_type_error(
        env,
        nullptr,
        "Expected source width, source height and frame listener");
    return nullptr;
  }

  int32_t sourceWidth = 0;
  int32_t sourceHeight = 0;
  napi_valuetype listenerType = napi_undefined;
  if (!ReadInt32(env, arguments[0], &sourceWidth) ||
      !ReadInt32(env, arguments[1], &sourceHeight) ||
      sourceWidth <= 0 || sourceHeight <= 0 ||
      sourceWidth % 2 != 0 || sourceHeight % 2 != 0 ||
      napi_typeof(env, arguments[2], &listenerType) != napi_ok ||
      listenerType != napi_function) {
    napi_throw_type_error(env, nullptr, "Native frame receiver arguments are invalid");
    return nullptr;
  }

  auto* receiver = new NativeFrameReceiver();
  std::string error;
  if (!receiver->Initialize(
      env,
      arguments[2],
      sourceWidth,
      sourceHeight,
      &error)) {
    delete receiver;
    napi_throw_error(env, nullptr, error.c_str());
    return nullptr;
  }

  napi_value result = nullptr;
  napi_create_object(env, &result);
  napi_property_descriptor descriptors[] = {
      {
          "getSurfaceId",
          nullptr,
          GetSurfaceId,
          nullptr,
          nullptr,
          nullptr,
          napi_default,
          nullptr
      },
      {
          "configure",
          nullptr,
          ConfigureReceiver,
          nullptr,
          nullptr,
          nullptr,
          napi_default,
          nullptr
      },
      {
          "release",
          nullptr,
          ReleaseReceiver,
          nullptr,
          nullptr,
          nullptr,
          napi_default,
          nullptr
      }
  };
  napi_define_properties(
      env,
      result,
      sizeof(descriptors) / sizeof(descriptors[0]),
      descriptors);
  napi_wrap(
      env,
      result,
      receiver,
      FinalizeReceiver,
      nullptr,
      nullptr);
  return result;
}
}  // namespace

namespace xmax {
void DefineNativeFrameReceiver(
    napi_env env,
    napi_value exports) {
  napi_property_descriptor descriptor = {
      "createFrameReceiver",
      nullptr,
      CreateFrameReceiver,
      nullptr,
      nullptr,
      nullptr,
      napi_default,
      nullptr
  };
  napi_define_properties(env, exports, 1, &descriptor);
}
}  // namespace xmax
