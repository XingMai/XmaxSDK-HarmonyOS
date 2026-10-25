#include "realtime_recorder.h"

#include <atomic>
#include <cmath>
#include <cstring>
#include <map>
#include <mutex>
#include <stdexcept>

#include "napi/native_api.h"

namespace {

struct Handle {
  std::shared_ptr<xlab::RealtimeRecorder> recorder;
  napi_threadsafe_function failure = nullptr;
};

std::mutex handlesMutex;
std::map<int64_t, Handle> handles;
std::atomic<int64_t> nextHandle{1};

void Require(napi_status status) {
  if (status != napi_ok) throw std::runtime_error("Invalid recorder argument");
}

napi_value Property(napi_env env, napi_value value, const char *name) {
  napi_value result;
  Require(napi_get_named_property(env, value, name, &result));
  return result;
}

int64_t Number(napi_env env, napi_value value) {
  double result = 0;
  Require(napi_get_value_double(env, value, &result));
  if (!std::isfinite(result) || result < 0 || result > 9007199254740991.0) {
    throw std::runtime_error("Invalid recording number");
  }
  return static_cast<int64_t>(std::llround(result));
}

int32_t IntProperty(napi_env env, napi_value value, const char *name) {
  const int64_t result = Number(env, Property(env, value, name));
  if (result > INT32_MAX) throw std::runtime_error("Recording value exceeds its range");
  return static_cast<int32_t>(result);
}

std::string String(napi_env env, napi_value value) {
  size_t size = 0;
  Require(napi_get_value_string_utf8(env, value, nullptr, 0, &size));
  std::vector<char> data(size + 1);
  Require(napi_get_value_string_utf8(env, value, data.data(), data.size(), &size));
  return std::string(data.data(), size);
}

Handle Find(napi_env env, napi_value id) {
  std::lock_guard<std::mutex> lock(handlesMutex);
  const auto found = handles.find(Number(env, id));
  if (found == handles.end()) throw std::runtime_error("Recording is no longer active");
  return found->second;
}

void DeliverError(napi_env env, napi_value callback, void *, void *data) {
  std::unique_ptr<std::string> message(static_cast<std::string *>(data));
  if (!env || !callback) return;
  napi_value text, ignored, receiver;
  napi_create_string_utf8(env, message->c_str(), message->size(), &text);
  napi_get_undefined(env, &receiver);
  napi_call_function(env, receiver, callback, 1, &text, &ignored);
}

napi_value Create(napi_env env, napi_callback_info info) {
  napi_threadsafe_function failure = nullptr;
  try {
    size_t argc = 2;
    napi_value args[2], name;
    Require(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));
    if (argc != 2) throw std::runtime_error("Recorder requires a path and error callback");
    const std::string path = String(env, args[0]);
    if (path.empty() || path.find('\0') != std::string::npos) throw std::runtime_error("Invalid recording path");
    Require(napi_create_string_utf8(env, "XLab recording failure", NAPI_AUTO_LENGTH, &name));
    Require(napi_create_threadsafe_function(env, args[1], nullptr, name, 1, 1,
        nullptr, nullptr, nullptr, DeliverError, &failure));

    auto recorder = std::make_shared<xlab::RealtimeRecorder>(path, [failure](std::string error) {
      auto *message = new std::string(std::move(error));
      if (napi_call_threadsafe_function(failure, message, napi_tsfn_nonblocking) != napi_ok) delete message;
    });
    const int64_t id = nextHandle++;
    {
      std::lock_guard<std::mutex> lock(handlesMutex);
      handles.emplace(id, Handle{std::move(recorder), failure});
    }
    napi_value result;
    napi_create_int64(env, id, &result);
    return result;
  } catch (const std::exception &error) {
    if (failure) napi_release_threadsafe_function(failure, napi_tsfn_abort);
    napi_throw_error(env, nullptr, error.what());
    return nullptr;
  }
}

void CopyPlane(napi_env env, napi_value plane, int width, int height, uint8_t *target) {
  void *data = nullptr;
  size_t size = 0;
  Require(napi_get_arraybuffer_info(env, Property(env, plane, "data"), &data, &size));
  const size_t offset = Number(env, Property(env, plane, "byteOffset"));
  const size_t length = Number(env, Property(env, plane, "byteLength"));
  const int stride = IntProperty(env, plane, "stride");
  const size_t needed = static_cast<size_t>(height - 1) * stride + width;
  if (!data || stride < width || offset > size || length > size - offset || needed > length) {
    throw std::runtime_error("Invalid recording video plane");
  }
  const auto *source = static_cast<uint8_t *>(data) + offset;
  for (int row = 0; row < height; row++) {
    std::memcpy(target + row * width, source + row * stride, width);
  }
}

napi_value AppendVideo(napi_env env, napi_callback_info info) {
  try {
    size_t argc = 2;
    napi_value args[2];
    Require(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));
    if (argc != 2) throw std::runtime_error("Missing recording frame");
    const Handle handle = Find(env, args[0]);
    xlab::RecordingPacket packet;
    packet.video = true;
    packet.timestampUs = Number(env, Property(env, args[1], "timestampUs"));
    packet.width = IntProperty(env, args[1], "width");
    packet.height = IntProperty(env, args[1], "height");
    packet.rotation = IntProperty(env, args[1], "rotation");
    if (String(env, Property(env, args[1], "pixelFormat")) != "i420" ||
        packet.width < 2 || packet.height < 2 || packet.width % 2 || packet.height % 2 ||
        static_cast<int64_t>(packet.width) * packet.height > 16777216 ||
        (packet.rotation != 0 && packet.rotation != 90 && packet.rotation != 180 && packet.rotation != 270)) {
      throw std::runtime_error("Invalid recording video format");
    }

    const size_t ySize = static_cast<size_t>(packet.width) * packet.height;
    packet.data.resize(ySize * 3 / 2);
    napi_value planes = Property(env, args[1], "planes");
    uint32_t count = 0;
    Require(napi_get_array_length(env, planes, &count));
    if (count != 3) throw std::runtime_error("I420 requires three planes");
    for (uint32_t i = 0; i < 3; i++) {
      napi_value plane;
      Require(napi_get_element(env, planes, i, &plane));
      CopyPlane(env, plane, i == 0 ? packet.width : packet.width / 2,
          i == 0 ? packet.height : packet.height / 2,
          packet.data.data() + (i == 0 ? 0 : i == 1 ? ySize : ySize + ySize / 4));
    }
    handle.recorder->Append(std::move(packet));
  } catch (const std::exception &error) {
    napi_throw_error(env, nullptr, error.what());
  }
  return nullptr;
}

napi_value AppendAudio(napi_env env, napi_callback_info info) {
  try {
    size_t argc = 2;
    napi_value args[2];
    Require(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));
    if (argc != 2) throw std::runtime_error("Missing recording audio");
    const Handle handle = Find(env, args[0]);
    xlab::RecordingPacket packet;
    packet.timestampUs = Number(env, Property(env, args[1], "timestampUs"));
    packet.sampleRate = IntProperty(env, args[1], "sampleRate");
    packet.channels = IntProperty(env, args[1], "channels");
    size_t length = 0, offset = 0;
    void *data = nullptr;
    napi_value storage;
    napi_typedarray_type type;
    Require(napi_get_typedarray_info(env, Property(env, args[1], "data"), &type, &length, &data, &storage, &offset));
    if (type != napi_uint8_array || !data || length == 0 || length > 1048576 ||
        packet.sampleRate < 8000 || packet.sampleRate > 192000 ||
        (packet.channels != 1 && packet.channels != 2) || length % (2 * packet.channels) != 0) {
      throw std::runtime_error("Invalid recording PCM");
    }
    packet.data.resize(length);
    std::memcpy(packet.data.data(), data, length);
    handle.recorder->Append(std::move(packet));
  } catch (const std::exception &error) {
    napi_throw_error(env, nullptr, error.what());
  }
  return nullptr;
}

struct FinishWork {
  Handle handle;
  bool cancel = false;
  std::string output, error;
  napi_deferred deferred = nullptr;
  napi_async_work work = nullptr;
};

void ExecuteFinish(napi_env, void *data) {
  auto &work = *static_cast<FinishWork *>(data);
  try { work.output = work.handle.recorder->Finish(work.cancel); }
  catch (const std::exception &error) { work.error = error.what(); }
  napi_release_threadsafe_function(work.handle.failure, napi_tsfn_release);
}

void CompleteFinish(napi_env env, napi_status status, void *data) {
  std::unique_ptr<FinishWork> work(static_cast<FinishWork *>(data));
  napi_value result;
  if (status == napi_ok && work->error.empty()) {
    napi_create_string_utf8(env, work->output.c_str(), work->output.size(), &result);
    napi_resolve_deferred(env, work->deferred, result);
  } else {
    napi_value message;
    const std::string reason = work->error.empty() ? "Recording finalization was cancelled" : work->error;
    napi_create_string_utf8(env, reason.c_str(), reason.size(), &message);
    napi_create_error(env, nullptr, message, &result);
    napi_reject_deferred(env, work->deferred, result);
  }
  napi_delete_async_work(env, work->work);
}

napi_value Finish(napi_env env, napi_callback_info info) {
  auto work = std::make_unique<FinishWork>();
  try {
    size_t argc = 2;
    napi_value args[2], promise, name;
    Require(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));
    if (argc != 2) throw std::runtime_error("Missing recording finish options");
    const int64_t id = Number(env, args[0]);
    Require(napi_get_value_bool(env, args[1], &work->cancel));
    work->handle = Find(env, args[0]);
    Require(napi_create_promise(env, &work->deferred, &promise));
    napi_create_string_utf8(env, "Finish XLab recording", NAPI_AUTO_LENGTH, &name);
    Require(napi_create_async_work(env, nullptr, name, ExecuteFinish, CompleteFinish, work.get(), &work->work));
    Require(napi_queue_async_work(env, work->work));
    {
      std::lock_guard<std::mutex> lock(handlesMutex);
      handles.erase(id);
    }
    work.release();
    return promise;
  } catch (const std::exception &error) {
    if (work->work) napi_delete_async_work(env, work->work);
    napi_throw_error(env, nullptr, error.what());
    return nullptr;
  }
}

napi_value Initialize(napi_env env, napi_value exports) {
  const napi_property_descriptor properties[] = {
      {"create", nullptr, Create, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"appendVideo", nullptr, AppendVideo, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"appendAudio", nullptr, AppendAudio, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"finish", nullptr, Finish, nullptr, nullptr, nullptr, napi_default, nullptr}};
  napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties);
  return exports;
}

napi_module module = {1, 0, nullptr, Initialize, "xlab_recorder", nullptr, {0}};

} // namespace

extern "C" __attribute__((constructor)) void RegisterXLabRecorder() {
  napi_module_register(&module);
}
