const test = require('node:test');
const assert = require('node:assert/strict');
const { loadEts } = require('./ets-loader.cjs');

test('RTC logs room and directed text signals without changing state and ignores stale rooms', () => {
  const logs = [];
  const load = loadEts({
    '@bytertc/volcenginertc': { MirrorType: { kMirrorTypeNone: 0 } },
    '@kit.ArkTS': {},
    RtcEngineManager: {}, RtcQualityConverter: {}, RtcStatsLogger: {}, RtcVideoConverter: {},
    XmaxLogger: { XmaxLogger: {
      debug(message, category) { logs.push({ message: message(), category }); }
    } }
  });
  const { RtcManager } = load('foundation/rtc/RtcManager.ets');
  const rtc = new RtcManager({});
  const handlers = new Map();
  const room = { on: (event, callback) => handlers.set(event, callback) };
  rtc.pendingRoom = room;
  rtc.bindRoomEvents(room);
  const payload = '{"event":"test_completed","task_id":"test-task"}';
  handlers.get('onRoomMessageReceived')('bot', payload);
  rtc.room = room;
  rtc.pendingRoom = null;
  handlers.get('onUserMessageReceived')('bot', payload);
  assert.equal(logs.length, 2);
  const formatted = JSON.stringify(JSON.parse(payload), null, 2).replace(/\n/g, '\n   ');
  for (const log of logs) {
    assert.equal(log.category, 'Room');
    assert.equal(log.message,
      `接收房间信令 (Receive Room Signal)\n├─ 类型：test_completed\n└─ 内容：\n   ${formatted}`);
  }
  handlers.get('onRoomMessageReceived')('bot', 'plain signal');
  assert.equal(logs[2].message, '接收房间信令 (Receive Room Signal)\n└─ 内容：plain signal');
  assert.equal(rtc.room, room);
  rtc.room = null;
  handlers.get('onRoomMessageReceived')('bot', payload);
  handlers.get('onUserMessageReceived')('bot', payload);
  assert.equal(logs.length, 3);
});
