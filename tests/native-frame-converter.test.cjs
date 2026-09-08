const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

test('native libyuv/NEON camera conversion preserves frame geometry and color', {
  skip: process.arch !== 'arm64' && 'Requires ARM64 to execute the NEON path'
}, () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'xmax-frame-converter-'));
  const cpp = path.resolve(__dirname, '../xmax_sdk/src/main/cpp');
  const libyuv = path.join(cpp, 'third_party/libyuv');
  const executable = path.join(directory, 'converter-test');
  try {
    const sourceFiles = fs.readdirSync(path.join(libyuv, 'source'))
      .filter(file => file.endsWith('.cc')).map(file => path.join(libyuv, 'source', file));
    const sanitizers = process.env.XMAX_NATIVE_SANITIZERS === '1'
      ? ['-fsanitize=address,undefined', '-fno-omit-frame-pointer'] : [];
    const compile = spawnSync(process.env.CXX || 'clang++', [
      '-std=c++17', '-O3', '-march=armv8.2-a+dotprod+i8mm',
      '-DLIBYUV_DISABLE_SME', '-DLIBYUV_DISABLE_SVE', ...sanitizers,
      '-I', cpp, '-I', path.join(libyuv, 'include'),
      path.join(__dirname, 'native/video-frame-converter.cpp'),
      path.join(cpp, 'video_frame_converter.cpp'),
      path.join(cpp, 'video_frame_geometry.cpp'),
      ...sourceFiles,
      '-o', executable
    ], { encoding: 'utf8', timeout: 120000 });
    assert.equal(compile.status, 0, compile.error?.message || compile.stderr);
    const run = spawnSync(executable, [], { encoding: 'utf8', timeout: 30000 });
    assert.equal(run.status, 0, run.error?.message || run.stderr);
    assert.match(run.stdout, /NEON conversion:.*passed/);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});
