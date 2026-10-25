//
//  native_remote_audio.cpp
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

#include "native_remote_audio.h"

#include <cmath>
#include <cstdint>
#include <cstring>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <unordered_set>
#include <vector>

#include "bytertc_engine.h"

namespace xmax {
namespace {

/** The shared delivery revision and byte budget, retained until queued PCM has been released. */
struct AudioDelivery {
  std::mutex mutex;
  bool active = false;
  uint64_t revision = 0;
  size_t bytes = 0;
  napi_threadsafe_function callback = nullptr;
  std::unordered_set<std::string> dropped;
};

/** An owned native PCM packet, including the native timestamp omitted by some RTC ArkTS bridges. */
struct AudioPacket {
  std::shared_ptr<AudioDelivery> delivery;
  uint64_t revision = 0;
  std::string room, user;
  int streamIndex = 0, sampleRate = 0, channels = 0;
  int64_t timestampUs = 0;
  bool discontinuous = false;
  std::vector<uint8_t> data;

  /** Releases this packet's queue budget even if its environment or binding has closed. */
  ~AudioPacket() {
    if (delivery) {
      std::lock_guard<std::mutex> lock(delivery->mutex);
      delivery->bytes -= data.size();
    }
  }
};

/** Creates a JavaScript number without changing the native microsecond time basis. */
napi_value Number(napi_env env, int64_t value) {
  napi_value result;
  napi_create_double(env, static_cast<double>(value), &result);
  return result;
}

/** Creates a copied JavaScript stream identifier. */
napi_value Text(napi_env env, const std::string &value) {
  napi_value result;
  napi_create_string_utf8(env, value.c_str(), value.size(), &result);
  return result;
}

/** Discards obsolete queued callbacks before allocating ArkTS PCM storage. */
void DeliverAudio(napi_env env, napi_value callback, void *, void *value) {
  std::unique_ptr<AudioPacket> packet(static_cast<AudioPacket *>(value));
  if (!env || !callback) return;
  {
    std::lock_guard<std::mutex> lock(packet->delivery->mutex);
    if (!packet->delivery->active || packet->revision != packet->delivery->revision) return;
  }

  napi_value bytes, discontinuous, receiver, ignored;
  void *storage = nullptr;
  if (napi_create_arraybuffer(env, packet->data.size(), &storage, &bytes) != napi_ok || !storage) return;
  std::memcpy(storage, packet->data.data(), packet->data.size());
  napi_get_boolean(env, packet->discontinuous, &discontinuous);
  napi_value arguments[] = {Text(env, packet->room), Text(env, packet->user), Number(env, packet->streamIndex),
      bytes, Number(env, packet->sampleRate), Number(env, packet->channels), Number(env, packet->timestampUs),
      discontinuous};
  napi_get_undefined(env, &receiver);
  napi_call_function(env, receiver, callback, 8, arguments, &ignored);
}

/** Owns one native observer for the RTC engine lease; disabled intervals invalidate queued delivery. */
class RemoteAudioObserver final : public bytertc::IAudioFrameObserver {
public:
  /** Creates a bounded, nonblocking bridge without registering an engine yet. */
  RemoteAudioObserver(napi_env env, napi_value listener) : delivery_(std::make_shared<AudioDelivery>()) {
    napi_value name;
    napi_create_string_utf8(env, "Xmax remote PCM", NAPI_AUTO_LENGTH, &name);
    if (napi_create_threadsafe_function(env, listener, nullptr, name, 128, 1, nullptr, nullptr,
        nullptr, DeliverAudio, &delivery_->callback) != napi_ok) {
      throw std::runtime_error("Cannot create native RTC audio delivery");
    }
  }

  /** Closes any remaining registration before releasing callback storage. */
  ~RemoteAudioObserver() override {
    Close();
    if (delivery_->callback) napi_release_threadsafe_function(delivery_->callback, napi_tsfn_abort);
  }

  /** Registers against the same engine acquired by the ArkTS RTC manager. */
  void Attach(bytertc::IRTCEngine *engine) {
    if (engine->registerAudioFrameObserver(this) != 0) {
      throw std::runtime_error("Register native RTC audio observer failed");
    }
    engine_ = engine;
  }

  /** Starts a new delivery revision or immediately invalidates the previous one. */
  void SetEnabled(bool enabled) {
    std::lock_guard<std::mutex> lock(delivery_->mutex);
    delivery_->active = enabled && engine_ != nullptr;
    delivery_->revision++;
    delivery_->dropped.clear();
  }

  /** Detaches while the manager still retains this observer through engine destruction. */
  int Close() {
    SetEnabled(false);
    auto *engine = engine_;
    engine_ = nullptr;
    return engine ? engine->registerAudioFrameObserver(nullptr) : 0;
  }

  /** Copies only unmixed remote PCM; capture and mixed output are intentionally ignored. */
  void onRemoteUserAudioFrame(const bytertc::RemoteStreamKey &key, const bytertc::IAudioFrame &frame) override {
    if (!key.room_id || !key.user_id || key.stream_index != bytertc::StreamIndex::kStreamIndexMain) return;
    std::string identity;
    try {
      identity = std::string(key.room_id) + '\0' + key.user_id;
      const int rate = static_cast<int>(frame.sampleRate()), channels = static_cast<int>(frame.channel());
      const int size = frame.dataSize();
      const int64_t timestamp = frame.timestampUs();
      const uint8_t *source = frame.data();
      const int samples = channels > 0 ? size / (channels * 2) : 0;
      if (frame.frameType() != bytertc::AudioFrameType::kAudioFrameTypePCM16 ||
          rate < 8000 || rate > 192000 || (channels != 1 && channels != 2) || !source ||
          size <= 0 || size % (channels * 2) != 0 || samples > 192000 ||
          timestamp < 0 || timestamp > 9007199254740991LL) {
        std::lock_guard<std::mutex> lock(delivery_->mutex);
        delivery_->dropped.insert(identity);
        return;
      }

      std::unique_ptr<AudioPacket> packet;
      {
        std::lock_guard<std::mutex> lock(delivery_->mutex);
        if (!delivery_->active) return;
        if (static_cast<size_t>(size) > 4 * 1024 * 1024 - delivery_->bytes) {
          delivery_->dropped.insert(identity);
          return;
        }

        packet = std::make_unique<AudioPacket>();
        packet->room = key.room_id;
        packet->user = key.user_id;
        packet->streamIndex = static_cast<int>(key.stream_index);
        packet->sampleRate = rate;
        packet->channels = channels;
        packet->timestampUs = timestamp;
        packet->revision = delivery_->revision;
        packet->discontinuous = delivery_->dropped.erase(identity) != 0;
        packet->data.assign(source, source + size);
        delivery_->bytes += size;
        packet->delivery = delivery_;
        if (napi_call_threadsafe_function(delivery_->callback, packet.get(), napi_tsfn_nonblocking) == napi_ok) {
          packet.release();
        } else {
          delivery_->dropped.insert(identity);
        }
      }
    } catch (...) {
      // Allocation failure must not escape the RTC playback thread.
      try {
        std::lock_guard<std::mutex> lock(delivery_->mutex);
        delivery_->dropped.insert(identity);
      } catch (...) {}
    }
  }

  /** Ignores original microphone PCM. */
  void onRecordAudioFrameOriginal(const bytertc::IAudioFrame &) override {}
  /** Ignores processed microphone PCM. */
  void onRecordAudioFrame(const bytertc::IAudioFrame &) override {}
  /** Ignores all-user playback mixing. */
  void onPlaybackAudioFrame(const bytertc::IAudioFrame &) override {}
  /** Ignores microphone and playback mixing. */
  void onMixedAudioFrame(const bytertc::IAudioFrame &) override {}
  /** Ignores local capture and media-player mixing. */
  void onCaptureMixedAudioFrame(const bytertc::IAudioFrame &) override {}

private:
  /** The engine remains valid until Close, before its lease is released. */
  bytertc::IRTCEngine *engine_ = nullptr;

  /** The synchronized callback state shared with queued packets. */
  std::shared_ptr<AudioDelivery> delivery_;
};

/** Resolves the opaque engine pointer returned by the platform's getNativeHandle. */
bytertc::IRTCEngine *Engine(napi_env env, napi_value value) {
  napi_valuetype type;
  napi_typeof(env, value, &type);
  void *pointer = nullptr;
  if (type == napi_external) {
    napi_get_value_external(env, value, &pointer);
  } else if (type == napi_bigint) {
    uint64_t address = 0;
    bool lossless = false;
    if (napi_get_value_bigint_uint64(env, value, &address, &lossless) == napi_ok && lossless)
      pointer = reinterpret_cast<void *>(static_cast<uintptr_t>(address));
  } else if (type == napi_number) {
    double address = 0;
    if (napi_get_value_double(env, value, &address) == napi_ok && std::isfinite(address) &&
        address > 0 && address <= 9007199254740991.0 && std::floor(address) == address)
      pointer = reinterpret_cast<void *>(static_cast<uintptr_t>(address));
  }
  if (!pointer) throw std::runtime_error("Invalid native RTC engine handle");
  return static_cast<bytertc::IRTCEngine *>(pointer);
}

/** Unwraps the engine-scoped observer for its ArkTS lifecycle methods. */
RemoteAudioObserver *Observer(napi_env env, napi_callback_info info, size_t *count, napi_value *arguments) {
  napi_value receiver;
  void *pointer = nullptr;
  if (napi_get_cb_info(env, info, count, arguments, &receiver, nullptr) != napi_ok ||
      napi_unwrap(env, receiver, &pointer) != napi_ok || !pointer)
    throw std::runtime_error("Invalid native RTC audio observer");
  return static_cast<RemoteAudioObserver *>(pointer);
}

/** Changes frame admission without unregistering the engine-scoped observer. */
napi_value SetEnabled(napi_env env, napi_callback_info info) {
  try {
    size_t count = 1;
    napi_value argument;
    auto *observer = Observer(env, info, &count, &argument);
    bool enabled = false;
    if (count != 1 || napi_get_value_bool(env, argument, &enabled) != napi_ok)
      throw std::runtime_error("Invalid native RTC audio observation state");
    observer->SetEnabled(enabled);
  } catch (const std::exception &error) {
    napi_throw_error(env, nullptr, error.what());
  }
  return nullptr;
}

/** Detaches native PCM delivery before RTC engine release. */
napi_value Close(napi_env env, napi_callback_info info) {
  try {
    size_t count = 0;
    const int result = Observer(env, info, &count, nullptr)->Close();
    if (result != 0) throw std::runtime_error("Unregister native RTC audio observer failed: " + std::to_string(result));
  } catch (const std::exception &error) {
    napi_throw_error(env, nullptr, error.what());
  }
  return nullptr;
}

/** Creates and wraps an observer before registering it against the native RTC engine. */
napi_value Create(napi_env env, napi_callback_info info) {
  try {
    size_t count = 2;
    napi_value arguments[2], object;
    if (napi_get_cb_info(env, info, &count, arguments, nullptr, nullptr) != napi_ok || count != 2)
      throw std::runtime_error("Native RTC audio requires an engine handle and listener");
    auto *engine = Engine(env, arguments[0]);
    auto observer = std::make_unique<RemoteAudioObserver>(env, arguments[1]);
    napi_create_object(env, &object);
    if (napi_wrap(env, object, observer.get(), [](napi_env, void *value, void *) {
      delete static_cast<RemoteAudioObserver *>(value);
    }, nullptr, nullptr) != napi_ok) throw std::runtime_error("Cannot wrap native RTC audio observer");
    auto *wrapped = observer.release();
    const napi_property_descriptor methods[] = {
        {"setEnabled", nullptr, SetEnabled, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"close", nullptr, Close, nullptr, nullptr, nullptr, napi_default, nullptr}};
    if (napi_define_properties(env, object, 2, methods) != napi_ok)
      throw std::runtime_error("Cannot define native RTC audio lifecycle");
    wrapped->Attach(engine);
    return object;
  } catch (const std::exception &error) {
    napi_throw_error(env, nullptr, error.what());
    return nullptr;
  }
}

} // namespace

void DefineNativeRemoteAudio(napi_env env, napi_value exports) {
  const napi_property_descriptor property{
      "createRtcRemoteAudioObserver", nullptr, Create, nullptr, nullptr, nullptr, napi_default, nullptr};
  napi_define_properties(env, exports, 1, &property);
}

} // namespace xmax
