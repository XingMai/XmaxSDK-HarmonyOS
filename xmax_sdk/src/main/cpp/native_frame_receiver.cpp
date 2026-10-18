//
//  native_frame_receiver.cpp
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
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

/**
 * 保存摄像头转换帧及错误信息，供跨线程交付到 ArkTS。
 */
struct FramePacket {

  /** 像素数据与帧布局 */
  std::unique_ptr<uint8_t[]> data;
  size_t dataLength = 0;
  int32_t width = 0;
  int32_t height = 0;

  /** 帧时间与错误通知 */
  int64_t timestampUs = 0;
  std::string error;
};

/**
 * 描述摄像头输出尺寸、旋转方向和帧率，并校验转换约束。
 */
struct OutputConfiguration {

  /** 目标尺寸与旋转 */
  int32_t width = 0;
  int32_t height = 0;
  int32_t rotation = 0;

  /** 输出与采集帧率 */
  int32_t frameRate = 0;
  int32_t captureFrameRate = 0;

  /**
   * 检查摄像头输出尺寸、旋转角度和帧率是否满足转换约束。
   *
   * @returns 配置可用于原生帧处理时返回 true。
   */
  bool IsValid() const {
    const bool rotationSupported = rotation == 0 || rotation == 90 ||
        rotation == 180 || rotation == 270;
    return width > 0 && height > 0 && width % 2 == 0 &&
        height % 2 == 0 && rotationSupported && frameRate > 0 &&
        captureFrameRate > 0 && frameRate <= captureFrameRate;
  }
};

/**
 * 接收 CameraKit 原始帧，在工作线程转换为 NV12 后交付给 ArkTS。
 */
class NativeFrameReceiver;

std::mutex receiverRegistryMutex;
std::unordered_map<OH_ImageReceiverNative*, NativeFrameReceiver*>
    receiverRegistry;

/**
 * 接收 CameraKit 原始帧，在工作线程转换为 NV12 后交付给 ArkTS。
 */
class NativeFrameReceiver {
 public:
  /**
   * 创建摄像头原始帧接收器。
   *
   * @returns 无返回值；完成实例初始化。
   */
  NativeFrameReceiver() = default;

  /**
   * 停止媒体输出并释放实例持有的原生资源与缓存。
   *
   * @returns 无返回值。
   */
  ~NativeFrameReceiver() {
    Stop();
  }

  /**
   * 创建并配置原生媒体资源，准备按目标规格输出媒体数据。
   *
   * @param env 当前 ArkTS N-API 执行环境。
   * @param listener 用于交付媒体帧、结束或错误通知的 ArkTS 函数。
   * @param sourceWidth 源图像宽度，单位像素。
   * @param sourceHeight 源图像高度，单位像素。
   * @param error 写入失败原因的字符串指针。
   * @returns 初始化成功时返回 true；失败返回 false 并写入错误说明。
   */
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

  /**
   * 读取供 CameraKit 绑定的接收 Surface 标识。
   *
   * @returns 当前原生接收 Surface 的标识引用。
   */
  const std::string& SurfaceId() const {
    return surfaceId_;
  }

  /**
   * 验证并更新摄像头目标尺寸、方向和帧率配置。
   *
   * @param width 画面宽度，单位像素。
   * @param height 画面高度，单位像素。
   * @param rotation 旋转角度，支持 0、90、180 或 270。
   * @param frameRate 目标输出帧率，单位 fps。
   * @param captureFrameRate 摄像头实际采集帧率，单位 fps。
   * @returns 配置有效并保存成功时返回 true，否则返回 false。
   */
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

  /**
   * 停止媒体输出与相关线程，并释放文件、系统媒体资源和回调引用。
   *
   * @returns 无返回值。
   */
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
   * 在系统通知新图像时唤醒对应接收器的工作线程。
   *
   * @param receiver 触发帧可用通知的系统图像接收器。
   * @returns 无返回值。
   */
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

    frameReceiver->frameAvailable_.store(true);
    frameReceiver->frameCondition_.notify_one();
  }

  /**
   * 在 ArkTS 线程交付媒体数据或状态通知，并按交付结果转移或释放数据包。
   *
   * @param env 当前 ArkTS N-API 执行环境。
   * @param callback 需要在 ArkTS 线程调用的函数。
   * @param data 关联的原生数据包或异步任务上下文。
   * @returns 无返回值。
   */
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
    napi_value arguments[5];
    for (auto& argument : arguments) {
      argument = undefined;
    }

    const bool hasError = !packet->error.empty();
    if (!hasError) {
      if (napi_create_external_arraybuffer(
          env,
          packet->data.get(),
          packet->dataLength,
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

  /**
   * 在 ArkTS 不再使用帧缓冲区时释放对应原生数据包。
   *
   * @param hint 关联到外部帧缓冲区、需要在回收时释放的数据包。
   * @returns 无返回值。
   */
  static void FinalizeFramePacket(
      napi_env,
      void*,
      void* hint) {
    delete static_cast<FramePacket*>(hint);
  }

  /**
   * 在接收器工作线程等待新帧，并使用最新输出配置处理图像。
   *
   * @returns 无返回值。
   */
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

  /**
   * 读取最新摄像头图像，并按目标采样帧率决定是否转换和交付。
   *
   * @returns 无返回值。
   */
  void ProcessFrame() {
    OutputConfiguration outputConfiguration;
    {
      std::lock_guard<std::mutex> lock(configurationMutex_);
      outputConfiguration = configuration_;
    }

    OH_ImageNative* image = nullptr;
    if (OH_ImageReceiverNative_ReadLatestImage(
        receiver_, &image) != IMAGE_SUCCESS || image == nullptr) {
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
    } catch (const std::exception& error) {
      ReportError(std::string("处理 Native 相机帧失败：") + error.what());
    } catch (...) {
      ReportError("处理 Native 相机帧失败：未知错误");
    }
    if (OH_ImageNative_Release(image) != IMAGE_SUCCESS) {
      ReportError("释放 Native 相机帧失败");
    }
  }

  /**
   * 读取摄像头原始图像的缓冲布局，完成映射并交给像素转换流程。
   *
   * @param image 当前取得的原始摄像头图像。
   * @param outputConfiguration 当前目标尺寸、旋转与采样帧率快照。
   * @returns 无返回值。
   */
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
        rowStride <= 0 || static_cast<uint32_t>(rowStride) < sourceSize.width) {
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

  /**
   * 校验已映射图像的布局和大小，转换为目标 NV12 帧并排队交付。
   *
   * @param address 已映射的图像缓冲区首地址。
   * @param bufferSize 已映射缓冲区的字节长度。
   * @param sourceSize 源图像的宽高。
   * @param rowStride 源图像每行的字节跨度。
   * @param timestamp 原始图像时间戳，单位纳秒。
   * @param outputConfiguration 当前目标尺寸、旋转与采样帧率快照。
   * @returns 无返回值。
   */
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
    auto packet = std::make_unique<FramePacket>();
    packet->dataLength = targetLumaLength + targetLumaLength / 2;
    // The converter writes every output byte; avoid a redundant zero fill.
    // Each delivery owns its storage until the external ArrayBuffer is finalized.
    packet->data.reset(new uint8_t[packet->dataLength]);
    packet->width = outputConfiguration.width;
    packet->height = outputConfiguration.height;
    packet->timestampUs = timestamp > 0 ? timestamp / 1000 :
        std::chrono::duration_cast<std::chrono::microseconds>(
            std::chrono::steady_clock::now().time_since_epoch()).count();

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
        packet->data.get(),
        configuration);

    Dispatch(packet.release());
  }

  /**
   * 根据采集与目标帧率累计采样进度，决定是否输出当前帧。
   *
   * @param outputConfiguration 当前目标尺寸、旋转与采样帧率快照。
   * @returns 当前帧应转换并交付时返回 true。
   */
  bool ShouldProcessFrame(
      const OutputConfiguration& outputConfiguration) {
    samplingAccumulator_ += outputConfiguration.frameRate;
    if (samplingAccumulator_ < outputConfiguration.captureFrameRate) {
      return false;
    }

    samplingAccumulator_ -= outputConfiguration.captureFrameRate;
    return true;
  }

  /**
   * 查询摄像头原始图像支持的分量类型。
   *
   * @param image 当前取得的原始摄像头图像。
   * @returns 可读取的图像分量类型；查询失败时通知错误并返回 0。
   */
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

  /**
   * 将摄像头处理错误封装为错误数据包并通知 ArkTS。
   *
   * @param message 需要交付或记录的错误原因。
   * @returns 无返回值。
   */
  void ReportError(const std::string& message) {
    auto* packet = new FramePacket();
    packet->error = message;
    Dispatch(packet);
  }

  /**
   * 将媒体数据包提交到 ArkTS 线程安全回调队列；提交失败时释放数据包。
   *
   * @param packet 需要消费、交付或释放的媒体数据包。
   * @returns 无返回值。
   */
  void Dispatch(FramePacket* packet) {
    if (listener_ == nullptr || napi_call_threadsafe_function(
        listener_, packet, napi_tsfn_nonblocking) != napi_ok) {
      delete packet;
    }
  }

  /** 系统接收资源与 ArkTS 回调 */
  OH_ImageReceiverNative* receiver_ = nullptr;
  napi_threadsafe_function listener_ = nullptr;
  std::string surfaceId_;
  bool listenerRegistered_ = false;

  /** 工作线程与帧可用同步 */
  std::atomic<bool> running_{false};
  std::atomic<bool> frameAvailable_{false};
  std::thread worker_;
  std::mutex frameMutex_;
  std::condition_variable frameCondition_;

  /** 输出配置并发保护 */
  std::mutex configurationMutex_;
  OutputConfiguration configuration_;

  /** 帧率采样与像素转换缓存 */
  int32_t samplingAccumulator_ = 0;

  uint32_t componentType_ = 0;
  xmax::VideoFrameTransformer transformer_;
};

/**
 * 从 ArkTS 数值中读取一个 32 位整数。
 *
 * @param env 当前 ArkTS N-API 执行环境。
 * @param value 待读取或计算的数值。
 * @param output 写入转换结果或提取值的目标地址。
 * @returns 参数可转换为 32 位整数时返回 true。
 */
bool ReadInt32(
    napi_env env,
    napi_value value,
    int32_t* output) {
  return napi_get_value_int32(env, value, output) == napi_ok;
}

/**
 * 从 ArkTS 方法调用中提取原生帧接收器及参数。
 *
 * @param env 当前 ArkTS N-API 执行环境。
 * @param info 当前 ArkTS 方法调用的参数与接收对象。
 * @param argumentCount 输入参数容量，并写回实际取得的参数数量。
 * @param arguments 接收 ArkTS 调用参数的数组。
 * @returns 原生接收器；提取失败时返回空指针并抛出 ArkTS 异常。
 */
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

/**
 * 在 ArkTS 接收器对象回收时删除原生接收器，释放采集资源。
 *
 * @param data 关联的原生数据包或异步任务上下文。
 * @returns 无返回值。
 */
void FinalizeReceiver(
    napi_env,
    void* data,
    void*) {
  delete static_cast<NativeFrameReceiver*>(data);
}

/**
 * 将原生接收器 Surface 标识返回给 ArkTS。
 *
 * @param env 当前 ArkTS N-API 执行环境。
 * @param info 当前 ArkTS 方法调用的参数与接收对象。
 * @returns Surface 标识字符串；调用无效时返回空值并抛出异常。
 */
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

/**
 * 解析 ArkTS 输出规格参数并更新原生帧接收器。
 *
 * @param env 当前 ArkTS N-API 执行环境。
 * @param info 当前 ArkTS 方法调用的参数与接收对象。
 * @returns ArkTS undefined；参数无效时抛出异常。
 */
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

/**
 * 停止并释放 ArkTS 对象绑定的原生帧接收器。
 *
 * @param env 当前 ArkTS N-API 执行环境。
 * @param info 当前 ArkTS 方法调用的参数与接收对象。
 * @returns ArkTS undefined。
 */
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

/**
 * 解析源尺寸与监听器，创建可被 CameraKit 使用的原生接收器对象。
 *
 * @param env 当前 ArkTS N-API 执行环境。
 * @param info 当前 ArkTS 方法调用的参数与接收对象。
 * @returns 包装原生接收器的 ArkTS 对象；失败时抛出异常。
 */
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
}  /** namespace */

namespace xmax {
/**
 * 向原生模块导出摄像头帧接收器的创建入口。
 *
 * @param env 当前 ArkTS N-API 执行环境。
 * @param exports 需要挂载 SDK 原生入口的模块导出对象。
 * @returns 无返回值。
 */
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
}  /** namespace xmax */
