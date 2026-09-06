const test = require('node:test');
const assert = require('node:assert/strict');
const { loadEts } = require('./ets-loader.cjs');

function fixture() {
  const logs = [], clockCalls = [];
  let now = 0, logFailure = false;
  const load = loadEts({
    '@ohos.systemDateTime': { default: { TimeType: { ACTIVE: 7 }, getUptime(type, nanos) {
      clockCalls.push([type, nanos]);
      return now * 1000000;
    } } },
    '@kit.PerformanceAnalysisKit': { hilog: { info(_domain, _tag, _format, message) {
      if (logFailure) throw new Error('logger unavailable');
      logs.push(message);
    } } }
  });
  const { XmaxLogger: Logger } = load('foundation/logging/XmaxLogger.ets');
  const { XmaxLoggerOption: Option } = load('foundation/logging/XmaxLoggerOption.ets');
  const { XmaxError, XmaxErrorCode: Code } = load('foundation/errors/XmaxError.ets');
  const { RealtimeTiming } = load('core/realtime/RealtimeTiming.ets');
  const timing = new RealtimeTiming();
  Logger.configure(Option.PERFORMANCE);
  return { logs, clockCalls, Logger, Option, XmaxError, Code, RealtimeTiming, timing,
    at(value) { now = value; }, failLogging() { logFailure = true; } };
}

test('startup timing uses monotonic nanoseconds and reports connection, signal and first-frame stages', () => {
  const f = fixture(), t = f.timing;
  t.begin();
  f.at(5); t.beginConnection();
  f.at(6); t.beginSessionCreation();
  f.at(26); t.finishSessionCreation();
  f.at(30); t.beginRoomJoin();
  f.at(70); t.finishRoomJoin();
  f.at(80); t.finishConnection();
  f.at(85); t.beginSignal('task');
  f.at(87); t.finishSignal('task');
  f.at(185); t.matchSEI('task');
  f.at(210); t.finish('task');
  assert.equal(f.logs.length, 1);
  for (const line of ['总耗时：210.0 ms', '实时连接：75.0 ms',
    '等待生成结果流确认：100.0 ms',
    '结果流确认到首帧就绪：25.0 ms']) assert.ok(f.logs[0].includes(line), line);
  assert.equal(f.logs[0].split('\n').length, 5);
  assert.doesNotMatch(f.logs[0], /调用与本地准备|服务端会话创建|RTC 房间连接|媒体发布与连接准备|连接后生成准备|生成前准备|发送生成请求/);
  assert.ok(f.logs[0].split('\n').every(line => line.startsWith('[Xmax][Timing]')));
  assert.ok(f.clockCalls.length > 0 && f.clockCalls.every(([type, nanos]) => type === 7 && nanos === true));
  t.finish('task');
  assert.equal(f.logs.length, 1);
});

test('only PERFORMANCE or ALL enables startup timing logs; reused connections omit connection timing', () => {
  const f = fixture();
  for (const option of [f.Option.NONE, f.Option.BUSINESS, f.Option.PERFORMANCE, f.Option.ALL]) {
    f.Logger.configure(option);
    f.at(0); f.timing.begin();
    f.at(0.1); f.timing.beginSignal('task');
    f.at(0.2); f.timing.finishSignal('task');
    f.at(10); f.timing.matchSEI('task');
    f.at(15); f.timing.finish('task');
  }
  assert.equal(f.logs.length, 2);
  assert.match(f.logs[0], /总耗时：15.0 ms/);
  assert.doesNotMatch(f.logs[0], /生成前准备|发送生成请求|实时连接：/);
});

test('failures report the pending stage and cancellation produces no failure log', () => {
  const cases = [
    [t => {}, '调用与本地准备'],
    [t => t.beginSessionCreation(), '服务端会话创建'],
    [t => { t.beginSessionCreation(); t.finishSessionCreation(); }, 'RTC 连接准备'],
    [t => { t.finishSessionCreation(); t.beginRoomJoin(); }, '正在连接 RTC 房间'],
    [t => t.finishConnection(), '连接完成后准备生成'],
    [t => t.beginSignal('task'), '正在等待生成结果流确认'],
    [t => { t.beginSignal('task'); t.matchSEI('task'); }, '结果流已确认，正在等待首帧']
  ];
  for (const [prepare, expected] of cases) {
    const f = fixture(), run = f.timing.begin();
    f.at(5); prepare(f.timing);
    f.at(15); f.timing.finishFailure(new f.XmaxError(f.Code.TIMEOUT, 'test failure'), run);
    assert.match(f.logs[0], /已耗时：15.0 ms/);
    assert.ok(f.logs[0].includes(`停留阶段：${expected}`));
    assert.match(f.logs[0], /失败原因：test failure/);
    f.timing.finishFailure(new f.XmaxError(f.Code.TIMEOUT, 'duplicate'), run);
    assert.equal(f.logs.length, 1);
  }
  const f = fixture(), run = f.timing.begin();
  f.timing.beginSignal('cancelled');
  f.timing.finishFailure(new f.XmaxError(f.Code.CANCELLED, 'cancelled'), run);
  f.timing.matchSEI('cancelled'); f.timing.finish('cancelled');
  assert.deepEqual(f.logs, []);
});

test('late failure from an older operation and wrong or repeated SEI cannot change a new measurement', () => {
  const f = fixture(), old = f.timing.begin();
  f.timing.beginSignal('old');
  f.at(50); f.timing.begin();
  f.at(55); f.timing.beginSignal('new');
  f.at(60); f.timing.finishFailure(new f.XmaxError(f.Code.CANCELLED, 'old cancelled'), old);
  f.timing.finishSignal('old'); f.timing.matchSEI('old'); f.timing.finish('old');
  f.at(65); f.timing.matchSEI('new');
  f.at(75); f.timing.matchSEI('new');
  f.at(80); f.timing.finish('new');
  assert.equal(f.logs.length, 1);
  assert.match(f.logs[0], /总耗时：30.0 ms/);
  assert.match(f.logs[0], /等待生成结果流确认：10.0 ms/);
  assert.match(f.logs[0], /结果流确认到首帧就绪：15.0 ms/);
});

test('explicit connection before a generation is not carried into the next startup measurement', () => {
  const f = fixture(), t = f.timing;
  t.beginConnection(); t.beginSessionCreation();
  f.at(1000); t.finishSessionCreation(); t.finishConnection();
  f.at(2000); t.begin(); t.beginSignal('task');
  f.at(2030); t.matchSEI('task'); f.at(2040); t.finish('task');
  assert.match(f.logs[0], /总耗时：40.0 ms/);
  assert.doesNotMatch(f.logs[0], /实时连接：|服务端会话创建/);
});

test('a failed operation stops accepting stages before its delayed cleanup report', () => {
  const f = fixture(), run = f.timing.begin();
  f.timing.beginSessionCreation();
  f.at(10); f.timing.endOperation(run);
  // A standalone reconnect may start before the old promise delivers its error report.
  f.at(20); f.timing.beginConnection(); f.timing.beginSessionCreation(); f.timing.finishConnection();
  f.at(30); f.timing.finishFailure(new f.XmaxError(f.Code.NETWORK_ERROR, 'old failure'), run);
  assert.equal(f.logs.length, 1);
  assert.match(f.logs[0], /停留阶段：服务端会话创建/);
  assert.doesNotMatch(f.logs[0], /实时连接：/);
});

test('diagnostic clock or logging failures do not escape into generation', () => {
  const f = fixture();
  for (const clock of [() => { throw new Error('clock unavailable'); }, () => NaN, () => Infinity]) {
    const timing = new f.RealtimeTiming(clock), run = timing.begin();
    timing.beginSignal('task'); timing.matchSEI('task'); timing.finish('task');
    timing.finishFailure(new Error('late failure'), run);
  }
  assert.deepEqual(f.logs, []);
  const run = f.timing.begin(); f.timing.beginSignal('task'); f.timing.matchSEI('task');
  f.failLogging();
  assert.doesNotThrow(() => f.timing.finish('task'));
  assert.doesNotThrow(() => f.timing.finishFailure(new Error('late failure'), run));
});
