const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

test('native RTC PCM preserves timestamps and ownership, bounds its queue, and invalidates obsolete delivery', () => {
  const source = fs.readFileSync(path.resolve(__dirname, '../xmax_sdk/src/main/cpp/native_remote_audio.cpp'), 'utf8');
  const methods = source.slice(source.indexOf('/** The shared delivery revision'),
    source.indexOf('/** Resolves the opaque engine pointer'));
  const template = fs.readFileSync(path.join(__dirname, 'native/rtc-remote-audio.cpp'), 'utf8');
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'xmax-rtc-pcm-'));
  try {
    const harness = path.join(temporary, 'observer.cpp'), executable = path.join(temporary, 'observer');
    fs.writeFileSync(harness, template.replace('// NATIVE_REMOTE_AUDIO', methods));
    const compile = spawnSync('clang++', ['-std=c++17', '-pthread', '-fsanitize=address,undefined',
      harness, '-o', executable], { encoding: 'utf8', timeout: 30000 });
    assert.equal(compile.status, 0, compile.error?.message || compile.stderr);
    const run = spawnSync(executable, [], { encoding: 'utf8', timeout: 15000 });
    assert.equal(run.status, 0, run.error?.message || run.stderr);
  } finally {
    fs.rmSync(temporary, { recursive: true, force: true });
  }
});
