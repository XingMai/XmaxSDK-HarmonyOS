const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { loadEts } = require('./ets-loader.cjs');
const app = path.resolve(__dirname, '../examples/XLab/entry/src/main');
const entries = locale => JSON.parse(fs.readFileSync(`${app}/resources/${locale}/element/string.json`, 'utf8')).string;
const strings = locale => Object.fromEntries(entries(locale).map(({name, value}) => [name, value]));

function fixture(initialLanguage = 'zh-CN') {
  let systemLanguage = initialLanguage;
  const storage = new Map(), persisted = new Map(), locales = [];
  const resources = {
    getConfigurationSync: () => ({ locale: systemLanguage }),
    getOverrideResourceManager: ({locale}) => {
      locales.push(locale);
      const data = strings(locale === 'zh-Hans' ? 'zh_Hans' : 'base');
      return { getStringByNameSync: key => {
        if (key === 'test_format') return '{0} / {1} / {0}';
        assert.ok(key in data, key);
        return data[key];
      } };
    }
  };
  const load = loadEts({
    '@kit.AbilityKit': {},
    '@kit.LocalizationKit': { i18n: { System: { getSystemLanguage: () => systemLanguage } } },
    '@xmax/sdk': { XmaxEnvironment: { CHINA: 'china', GLOBAL: 'global' } }
  }, {
    AppStorage: { get: key => storage.get(key), setOrCreate: (key, value) => {
      storage.set(key, value);
      if (persisted.has(key)) persisted.set(key, value);
    } },
    PersistentStorage: { persistProp: (key, value) => {
      if (!persisted.has(key)) persisted.set(key, value);
      if (!storage.has(key)) storage.set(key, persisted.get(key));
    } }
  });
  const { XLabLocalization: L, XLabLanguage: Language } = load(`${app}/ets/localization/XLabLocalization.ets`);
  L.initialize({ resourceManager: resources });
  return { L, Language, storage, locales, resources, setSystem: value => { systemLanguage = value; } };
}

test('XLab follows system Chinese and falls back to English for other languages', () => {
  const f = fixture();
  assert.equal(f.L.environment, 'china');
  assert.equal(f.L.languageCode, 'zh-Hans');
  const chinese = f.L.text('choose_model');
  const revision = f.storage.get(f.L.REVISION_KEY);
  f.L.refresh(); f.L.text('choose_model');
  assert.equal(f.storage.get(f.L.REVISION_KEY), revision);
  f.setSystem('fr-FR'); f.L.refresh();
  assert.equal(f.L.environment, 'global');
  assert.equal(f.L.languageCode, 'en');
  assert.equal(f.L.text('choose_model'), strings('base').choose_model);
  assert.notEqual(f.L.text('choose_model'), chinese);
  assert.equal(f.storage.get(f.L.REVISION_KEY), revision + 1);
  f.setSystem('zh-Hant-TW'); f.L.refresh();
  assert.equal(f.L.environment, 'china');
});

test('explicit language survives system changes and storage restoration', () => {
  const f = fixture('en-US');
  f.L.setLanguage(f.Language.CHINESE);
  f.setSystem('de-DE'); f.L.refresh();
  assert.equal(f.L.environment, 'china');
  const revision = f.storage.get(f.L.REVISION_KEY);
  f.storage.delete(f.L.LANGUAGE_KEY);
  f.L.initialize({ resourceManager: f.resources });
  assert.equal(f.L.language, f.Language.CHINESE);
  assert.ok(f.storage.get(f.L.REVISION_KEY) > revision);
  f.L.setLanguage(f.Language.ENGLISH);
  f.setSystem('zh-CN'); f.L.refresh();
  assert.equal(f.L.environment, 'global');
  f.L.setLanguage(f.Language.SYSTEM);
  assert.equal(f.L.environment, 'china');
});

test('localized formatting preserves user values containing placeholders', () => {
  const { L } = fixture();
  assert.equal(L.format('test_format', ['{1} $& 中文', 'second']), '{1} $& 中文 / second / {1} $& 中文');
  assert.equal(L.format('test_format', ['first']), 'first / {1} / first');
});

test('language resources have matching keys and placeholders, and cover all static UI references', () => {
  const en = strings('base'), zh = strings('zh_Hans');
  assert.equal(entries('base').length, Object.keys(en).length);
  assert.equal(entries('zh_Hans').length, Object.keys(zh).length);
  assert.deepEqual(Object.keys(en).sort(), Object.keys(zh).sort());
  for (const key of Object.keys(en)) {
    assert.ok(en[key].trim(), key); assert.ok(zh[key].trim(), key);
    assert.deepEqual(en[key].match(/\{\d+\}/g), zh[key].match(/\{\d+\}/g), key);
  }
  function scan(directory) {
    for (const entry of fs.readdirSync(directory, {withFileTypes: true})) {
      const file = path.join(directory, entry.name);
      if (entry.isDirectory()) scan(file);
      else if (file.endsWith('.ets')) {
        const text = fs.readFileSync(file, 'utf8');
        for (const match of text.matchAll(/(?:this\.text|XLabLocalization\.(?:text|format))\('([^']+)'/g)) {
          assert.ok(match[1] in en, `${file}: ${match[1]}`);
        }
      }
    }
  }
  scan(`${app}/ets`);
});
