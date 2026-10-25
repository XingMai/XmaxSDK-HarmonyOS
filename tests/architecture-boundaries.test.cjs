const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const sdk = path.resolve(__dirname, '../xmax_sdk');
const root = path.join(sdk, 'src/main/ets');

function files(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
    const file = path.join(directory, entry.name);
    return entry.isDirectory() ? files(file) : file.endsWith('.ets') ? [file] : [];
  });
}

function imports(file) {
  const source = fs.readFileSync(file, 'utf8');
  return [...source.matchAll(/\bfrom\s*['"](\.[^'"]+)['"]/g)].map(match =>
    path.resolve(path.dirname(file), `${match[1]}.ets`));
}

test('all SDK relative imports and public re-exports resolve after the layer moves', () => {
  for (const file of [...files(root), path.join(sdk, 'Index.ets')]) {
    for (const dependency of imports(file)) {
      assert.ok(fs.existsSync(dependency), `${path.relative(sdk, file)} -> ${path.relative(sdk, dependency)}`);
    }
  }
});

test('SDK layers do not import Core; Foundation and Service retain downward-only dependencies', () => {
  const allowed = {
    foundation: new Set(['foundation']),
    service: new Set(['service', 'foundation'])
  };
  for (const file of files(root)) {
    const relative = path.relative(root, file), layer = relative.split(path.sep)[0];
    for (const dependency of imports(file)) {
      // Generated build metadata is not an SDK capability layer.
      if (dependency === path.join(sdk, 'BuildProfile.ets')) continue;
      const target = path.relative(root, dependency).split(path.sep)[0];
      if (layer !== 'core') assert.notEqual(target, 'core', `${relative} imports Core`);
      if (allowed[layer]) assert.ok(allowed[layer].has(target), `${relative} imports ${target}`);
    }
  }
});

test('business models, timing, raw pixels and lifecycle management have one canonical location', () => {
  const moves = [
    ['core/realtime/RealtimeModel.ets', 'service/realtime/RealtimeModel.ets'],
    ['core/realtime/RealtimeTiming.ets', 'service/realtime/RealtimeTiming.ets'],
    ['service/realtime/RealtimeMediaSource.ets', 'service/media/RealtimeMediaSource.ets'],
    ['service/realtime/RealtimeVideoFrame.ets', 'foundation/media/video/RealtimeVideoFrame.ets'],
    ['core/realtime/RealtimeCoordinator.ets', 'core/realtime/XmaxRealtimeLifecycleManager.ets']
  ];
  for (const [before, after] of moves) {
    assert.equal(fs.existsSync(path.join(root, before)), false, before);
    assert.equal(fs.existsSync(path.join(root, after)), true, after);
  }

  const entry = fs.readFileSync(path.join(sdk, 'Index.ets'), 'utf8');
  assert.match(entry, /export\s*\{\s*RealtimeModel,\s*ModelDefinition,\s*RealtimeModels\s*\}\s*from\s*'\.\/src\/main\/ets\/service\/realtime\/RealtimeModel'/);
  assert.match(entry, /export\s*\{\s*RealtimeMediaSource\s*\}\s*from\s*'\.\/src\/main\/ets\/service\/media\/RealtimeMediaSource'/);
  assert.match(entry, /export\s*\{\s*RealtimeVideoFrame\s*\}\s*from\s*'\.\/src\/main\/ets\/foundation\/media\/video\/RealtimeVideoFrame'/);
  assert.doesNotMatch(entry, /XmaxRealtimeLifecycleManager|RealtimeTiming|XmaxLogLanguage/);
});
