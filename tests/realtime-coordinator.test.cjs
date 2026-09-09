const test = require('node:test');
const assert = require('node:assert/strict');
const { loadEts } = require('./ets-loader.cjs');

const settle = async () => { for (let i = 0; i < 40; i++) await Promise.resolve(); };
const outcome = promise => promise.then(value => ({ value }), error => ({ error }));
function gate() {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}
function fixture(cleanup) {
  const events = [], states = [], errors = [], logs = [];
  const load = loadEts({ XmaxLogger: { XmaxLogger: { error: (...args) => logs.push(args) } } });
  const { XmaxError, XmaxErrorCode: Code, XmaxErrorSeverity: Severity } = load('foundation/errors/XmaxError.ets');
  const { RealtimeState, RealtimeConnectionState: State, RealtimeDisconnectionReason: Reason } = load('service/realtime/RealtimeState.ets');
  const { XmaxRealtimeErrorManager } = load('core/realtime/XmaxRealtimeErrorManager.ets');
  const { RealtimeCoordinator, RealtimeOperationKind: Kind, RealtimeTerminationScope: Scope } =
    load('core/realtime/RealtimeCoordinator.ets');
  const handler = new XmaxRealtimeErrorManager();
  handler.setListener(error => { events.push('error'); errors.push(error); });
  const coordinator = new RealtimeCoordinator(handler, async (scope, task) => {
    events.push(`cleanup:${scope}:${task}`);
    return cleanup?.(scope, task);
  });
  coordinator.setStateListener(state => { states.push(state); events.push(`state:${state.connectionState}`); });
  return { coordinator, handler, Kind, Scope, State, Reason, RealtimeState, XmaxError, Code, Severity,
    events, states, errors, logs };
}

test('orientation disconnection reason survives a synchronous close escalation and clears on reconnect', async () => {
  const f = fixture();
  await f.coordinator.run(f.Kind.CONNECTION, f.Scope.CONNECTION, async token => {
    f.coordinator.commit(new f.RealtimeState(f.State.CONNECTED, 'session'), token);
  });
  const states = [];
  f.coordinator.setStateListener(state => {
    states.push(state);
    if (state.connectionState === f.State.DISCONNECTING) {
      void f.coordinator.terminate(f.Scope.ALL, f.State.DISCONNECTED);
    }
  });
  await f.coordinator.terminate(f.Scope.CONNECTION, f.State.DISCONNECTED, f.Reason.CAMERA_ORIENTATION_CHANGED);
  assert.ok(f.events.includes(`cleanup:${f.Scope.ALL}:`));
  assert.deepEqual(states.slice(-2).map(state => [state.connectionState, state.disconnectionReason]), [
    [f.State.DISCONNECTING, f.Reason.CAMERA_ORIENTATION_CHANGED],
    [f.State.DISCONNECTED, f.Reason.CAMERA_ORIENTATION_CHANGED]
  ]);
  await f.coordinator.run(f.Kind.CONNECTION, f.Scope.CONNECTION, async token => {
    f.coordinator.commit(new f.RealtimeState(f.State.CONNECTED, 'next'), token);
  });
  assert.equal(f.coordinator.currentState.disconnectionReason, undefined);
});

test('normal disconnect and close report NORMAL, while stopped generation and ERROR have no reason', async () => {
  for (const scope of ['CONNECTION', 'ALL']) {
    const f = fixture();
    await f.coordinator.run(f.Kind.CONNECTION, f.Scope.CONNECTION, async token => {
      f.coordinator.commit(new f.RealtimeState(f.State.GENERATING, 'session', 'task'), token);
    });
    await f.coordinator.terminate(f.Scope.GENERATION);
    assert.equal(f.coordinator.currentState.connectionState, f.State.CONNECTED);
    assert.equal(f.coordinator.currentState.disconnectionReason, undefined);
    await f.coordinator.terminate(f.Scope[scope], f.State.DISCONNECTED);
    assert.deepEqual(f.states.slice(-2).map(state => [state.connectionState, state.disconnectionReason]), [
      [f.State.DISCONNECTING, f.Reason.NORMAL],
      [f.State.DISCONNECTED, f.Reason.NORMAL]
    ]);
    await f.coordinator.run(f.Kind.CONNECTION, f.Scope.CONNECTION, async token => {
      f.coordinator.commit(new f.RealtimeState(f.State.CONNECTED, 'next'), token);
    });
    assert.equal(f.coordinator.currentState.disconnectionReason, undefined);
    await f.coordinator.terminateWithError(new f.XmaxError(f.Code.TIMEOUT, 'connection failed'), f.Scope.CONNECTION);
    assert.equal(f.coordinator.currentState.connectionState, f.State.ERROR);
    assert.equal(f.coordinator.currentState.disconnectionReason, undefined);
    assert.equal(f.states.at(-2).disconnectionReason, undefined);
  }
});

test('one operation owns the lifecycle and overlapping calls are rejected before executing', async () => {
  const f = fixture(), blocked = gate();
  const first = f.coordinator.run(f.Kind.MEDIA, f.Scope.ALL, async () => blocked.promise);
  let executed = false;
  await assert.rejects(f.coordinator.run(f.Kind.CONNECTION, f.Scope.CONNECTION, async () => {
    executed = true;
  }), { code: f.Code.INVALID_CONFIGURATION });
  assert.equal(executed, false);
  blocked.resolve(42);
  assert.equal(await first, 42);
  assert.deepEqual(f.errors, []);
  assert.equal(await f.coordinator.run(f.Kind.MEDIA, f.Scope.ALL, async () => 7), 7);
});

test('close invalidates stale commits and awaits non-cancellable resource creation before cleanup', async () => {
  const f = fixture(), creation = gate();
  let token;
  const running = outcome(f.coordinator.run(f.Kind.CONNECTION, f.Scope.CONNECTION, async current => {
    token = current;
    f.coordinator.commit(new f.RealtimeState(f.State.CONNECTING), current);
    await creation.promise;
    f.coordinator.commit(new f.RealtimeState(f.State.CONNECTED, 'old-session'), current);
  }));
  const closing = f.coordinator.terminate(f.Scope.ALL, f.State.DISCONNECTED);
  assert.equal(f.coordinator.terminate(f.Scope.CONNECTION, f.State.DISCONNECTED), closing);
  await settle();
  assert.equal(f.events.some(event => event.startsWith('cleanup:')), false);
  creation.resolve();
  await closing;
  assert.equal((await running).error.code, f.Code.CANCELLED);
  assert.equal(f.coordinator.currentState.connectionState, f.State.DISCONNECTED);
  assert.equal(f.states.some(state => state.connectionState === f.State.CONNECTED), false);
  assert.throws(() => f.coordinator.commit(new f.RealtimeState(f.State.GENERATING), token),
    { code: f.Code.CANCELLED });
  await f.coordinator.run(f.Kind.MEDIA, f.Scope.ALL, async () => {});
});

test('fatal generation failure narrows cleanup, commits ERROR and then reports the original error', async () => {
  const f = fixture();
  const original = new f.XmaxError(f.Code.TIMEOUT, 'first frame', 1004, 504);
  await assert.rejects(f.coordinator.run(f.Kind.GENERATION, f.Scope.CONNECTION, async token => {
    f.coordinator.commit(new f.RealtimeState(f.State.CONNECTED, 'session'), token);
    token.setFailureScope(f.Scope.GENERATION);
    throw original;
  }), error => error === original);
  assert.deepEqual(f.events.slice(-3), [`cleanup:${f.Scope.GENERATION}:`, `state:${f.State.ERROR}`, 'error']);
  assert.deepEqual(f.errors, [original]);
  assert.equal(f.coordinator.currentState.sessionId, 'session');
});

test('recoverable operation errors leave resources and public state intact', async () => {
  const f = fixture();
  const original = new f.XmaxError(f.Code.INVALID_CONFIGURATION, 'bad input');
  await assert.rejects(f.coordinator.run(f.Kind.MEDIA, f.Scope.ALL, async () => { throw original; }),
    error => error === original);
  assert.deepEqual(f.events, [`state:${f.State.IDLE}`]);
  assert.deepEqual(f.errors, []);
});

test('background fatal error interrupts a readiness wait and survives cancellation unchanged', async () => {
  const f = fixture(), readiness = gate();
  const running = outcome(f.coordinator.run(f.Kind.GENERATION, f.Scope.GENERATION,
    token => token.wait(readiness.promise)));
  const original = new f.XmaxError(f.Code.SESSION_ERROR, 'heartbeat lost', 123, 503);
  await f.coordinator.terminateWithError(original, f.Scope.CONNECTION);
  assert.equal((await running).error, original);
  assert.deepEqual(f.errors, [original]);
  assert.ok(f.events.indexOf(`cleanup:${f.Scope.CONNECTION}:`) < f.events.indexOf('error'));
  readiness.reject(new Error('late failure')); // Must be observed after cancellation.
  await settle();
});

test('concurrent stop/disconnect/close share one task and upgrade cleanup while it is suspended', async () => {
  const cleanup = gate();
  const f = fixture(async scope => { if (scope === 0) await cleanup.promise; return 'session'; });
  const stopping = f.coordinator.terminate(f.Scope.GENERATION);
  await settle();
  assert.equal(f.coordinator.terminate(f.Scope.CONNECTION, f.State.DISCONNECTED), stopping);
  assert.equal(f.coordinator.terminate(f.Scope.ALL, f.State.DISCONNECTED), stopping);
  await assert.rejects(f.coordinator.run(f.Kind.MEDIA, f.Scope.ALL, async () => {}),
    { code: f.Code.INVALID_CONFIGURATION });
  cleanup.resolve();
  await stopping;
  assert.deepEqual(f.events.filter(event => event.startsWith('cleanup:')),
    [`cleanup:${f.Scope.GENERATION}:`, `cleanup:${f.Scope.ALL}:`]);
  assert.equal(f.coordinator.currentState.connectionState, f.State.DISCONNECTED);
  assert.equal(f.coordinator.currentState.sessionId, 'session');
  await f.coordinator.run(f.Kind.MEDIA, f.Scope.ALL, async () => {});
});

test('a synchronous final-state listener can escalate to close without losing the extra cleanup', async () => {
  const f = fixture();
  await f.coordinator.run(f.Kind.GENERATION, f.Scope.GENERATION, async token => {
    f.coordinator.commit(new f.RealtimeState(f.State.GENERATING, 'session', 'task'), token);
  });
  let closing;
  f.coordinator.setStateListener(state => {
    if (state.connectionState === f.State.CONNECTED) {
      closing = f.coordinator.terminate(f.Scope.ALL, f.State.DISCONNECTED);
    }
    if (state.connectionState === f.State.DISCONNECTED) {
      f.coordinator.terminate(f.Scope.ALL, f.State.DISCONNECTED);
    }
  });
  const stopping = f.coordinator.terminate(f.Scope.GENERATION);
  await stopping;
  assert.equal(closing, stopping);
  assert.deepEqual(f.events.filter(event => event.startsWith('cleanup:')),
    [`cleanup:${f.Scope.GENERATION}:task`, `cleanup:${f.Scope.ALL}:`]);
  assert.equal(f.coordinator.currentState.connectionState, f.State.DISCONNECTED);
});

test('fatal callback can close resources; explicit disconnect wins and error is reported once', async () => {
  const f = fixture();
  const original = new f.XmaxError(f.Code.RTC_ERROR, 'lost');
  f.handler.setListener(error => {
    f.errors.push(error);
    f.coordinator.terminate(f.Scope.ALL, f.State.DISCONNECTED);
  });
  await f.coordinator.terminateWithError(original, f.Scope.GENERATION);
  assert.deepEqual(f.errors, [original]);
  assert.equal(f.coordinator.currentState.connectionState, f.State.DISCONNECTED);
  assert.deepEqual(f.events.filter(event => event.startsWith('cleanup:')),
    [`cleanup:${f.Scope.GENERATION}:`, `cleanup:${f.Scope.ALL}:`]);
});

test('completed tokens cannot commit and equal states do not notify twice', async () => {
  const f = fixture();
  let retained;
  await f.coordinator.run(f.Kind.CONNECTION, f.Scope.CONNECTION, async token => {
    retained = token;
    const state = new f.RealtimeState(f.State.CONNECTED, 'session');
    f.coordinator.commit(state, token);
    f.coordinator.commit(new f.RealtimeState(f.State.CONNECTED, 'session'), token);
  });
  assert.equal(f.states.length, 2);
  assert.throws(() => f.coordinator.commit(new f.RealtimeState(f.State.ERROR), retained),
    { code: f.Code.CANCELLED });
});
