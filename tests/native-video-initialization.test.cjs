const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

test('native video initialization and failure cleanup execute on the worker, not the caller', () => {
  const source = fs.readFileSync(path.join(__dirname,
    '../xmax_sdk/src/main/cpp/native_video_file_decoder.cpp'), 'utf8');
  const worker = source.slice(source.indexOf('void ExecuteCreateDecoder('),
    source.indexOf('void CompleteCreateDecoder('));
  const entry = source.slice(source.indexOf('napi_value CreateVideoFileDecoder('));
  assert.match(entry, /napi_create_async_work\(env, nullptr, resourceName, ExecuteCreateDecoder/);
  assert.doesNotMatch(entry, /decoder->Initialize\(/);
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'xmax-video-init-'));
  try {
    const harness = path.join(directory, 'init.cpp');
    const executable = path.join(directory, 'init');
    fs.writeFileSync(harness, `
#include <cassert>
#include <cstdint>
#include <string>
#include <thread>
using napi_env = void*;
struct Decoder {
  bool succeeds = true;
  std::thread::id initializedOn, releasedOn;
  bool Initialize(int64_t, int64_t, int64_t, int32_t, int32_t, int32_t,
      int64_t, int64_t, std::string* error) {
    initializedOn = std::this_thread::get_id();
    if (!succeeds) *error = "codec setup failed";
    return succeeds;
  }
  void Stop() { releasedOn = std::this_thread::get_id(); }
};
struct CreateDecoderContext {
  Decoder* decoder;
  int64_t size = 1000, anchorUs = 1, mediaStartUs = 0;
  int32_t rotation = 0, width = 2, height = 2;
  int64_t frameIntervalUs = 33333, cycleDurationUs = 1000000;
  std::string error;
};
${worker}
int main() {
  const auto caller = std::this_thread::get_id();
  for (bool succeeds : {true, false}) {
    Decoder decoder;
    decoder.succeeds = succeeds;
    CreateDecoderContext context{&decoder};
    std::thread worker([&] { ExecuteCreateDecoder(nullptr, &context); });
    worker.join();
    assert(decoder.initializedOn != caller);
    if (succeeds) {
      assert(context.error.empty() && decoder.releasedOn == std::thread::id{});
    } else {
      assert(!context.error.empty() && decoder.releasedOn == decoder.initializedOn);
    }
  }
}
`);
    const compiled = spawnSync(process.env.CXX || 'clang++',
      ['-std=c++17', '-pthread', harness, '-o', executable], { encoding: 'utf8', timeout: 30000 });
    assert.equal(compiled.status, 0, compiled.error?.message || compiled.stderr);
    const run = spawnSync(executable, [], { encoding: 'utf8', timeout: 10000 });
    assert.equal(run.status, 0, run.error?.message || run.stderr);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});
