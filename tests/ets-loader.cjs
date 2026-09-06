// Executes ordinary SDK logic on Node; platform APIs are supplied explicitly by each test.
// ArkUI build() remains covered by the HAR/HAP compiler and device verification.
const fs = require('node:fs');
const path = require('node:path');
const ts = require(process.env.TYPESCRIPT_PATH ||
  '/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript');
const root = path.resolve(__dirname, '../xmax_sdk/src/main/ets');

function loadEts(stubs = {}, globals = {}) {
  const cache = new Map();
  function load(file) {
    const full = path.resolve(root, file);
    if (cache.has(full)) return cache.get(full).exports;
    let source = fs.readFileSync(full, 'utf8');
    if (source.includes('export struct ')) {
      // Only lifecycle/state methods are executed here, without emulating ArkUI rendering.
      const begin = source.indexOf('  build() {');
      let end = source.indexOf('{', begin), depth = 1;
      while (depth && ++end < source.length) {
        if (source[end] === '{') depth++;
        if (source[end] === '}') depth--;
      }
      source = source.slice(0, begin) + source.slice(end + 1);
      source = source.replace('export struct ', 'export class ')
        .replace(/@(?:Component|State|Prop)\b/g, '').replace(/@Watch\('[^']+'\)/g, '');
    }
    const output = ts.transpileModule(source, { compilerOptions: {
      target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS,
      experimentalDecorators: true
    } }).outputText;
    const module = { exports: {} };
    cache.set(full, module);
    const localRequire = spec => {
      const stub = stubs[spec] ?? stubs[path.basename(spec)];
      if (stub !== undefined) return stub;
      if (spec.startsWith('@')) throw new Error(`Missing platform stub: ${spec}`);
      return load(path.resolve(path.dirname(full), `${spec}.ets`));
    };
    new Function('require', 'module', 'exports', ...Object.keys(globals), output)(
      localRequire, module, module.exports, ...Object.values(globals));
    return module.exports;
  }
  return load;
}
module.exports = { loadEts };
