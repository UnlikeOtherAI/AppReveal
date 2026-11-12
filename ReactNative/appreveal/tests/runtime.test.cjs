const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const ts = require('typescript');

function load(native, fetch = async () => new Response('ok')) {
  const exports = {};
  const context = { exports, __DEV__: true, URL, Request, Response, Headers, fetch,
    require(name) {
      if (name === 'react') return { useEffect() {} };
      if (name === './NativeAppReveal') return { default: native, __esModule: true };
      throw new Error(name);
    } };
  vm.runInNewContext(ts.transpileModule(fs.readFileSync('src/index.ts', 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
  return { api: exports, context };
}

test('fetch preserves success and the original rejection when telemetry fails', async () => {
  const response = new Response('body');
  const { api, context } = load({ captureNetworkCall() { throw new Error('bridge absent'); } }, async () => response);
  api.AppRevealFetchInterceptor.install();
  assert.equal(await context.fetch('https://example.test'), response);
  assert.equal(await response.text(), 'body');
  const original = new Error('offline');
  const failed = load({ captureNetworkCall() { throw new Error('bridge absent'); } }, async () => { throw original; });
  failed.api.AppRevealFetchInterceptor.install();
  await assert.rejects(failed.context.fetch('https://example.test'), error => error === original);
});

test('Request headers and timing survive fetch instrumentation', async () => {
  const calls = [];
  const { api, context } = load({ captureNetworkCall(call) { calls.push(call); } });
  api.AppRevealFetchInterceptor.install();
  const patched = context.fetch;
  api.AppRevealFetchInterceptor.install();
  assert.equal(context.fetch, patched);
  await context.fetch(new Request('https://example.test', { method: 'POST', headers: { 'X-Test': 'retained' } }));
  assert.equal(calls.length, 1);
  assert.equal(calls[0].method, 'POST');
  assert.equal(calls[0].requestHeaders['x-test'], 'retained');
  assert.ok(calls[0].responseTimestamp >= calls[0].requestTimestamp);
});

test('port validation rejects values that would trap UInt16 on iOS', () => {
  const ports = [];
  const { api } = load({ start(port) { ports.push(port); } });
  for (const port of [-1, 65536, 1.5, NaN, Infinity]) assert.throws(() => api.AppReveal.start(port), /port must/);
  api.AppReveal.start(0);
  api.AppReveal.start(65535);
  assert.deepEqual(ports, [0, 65535]);
});


test('navigation listener accepts restored partial nested state', () => {
  const screens = [];
  const { api } = load({ setScreen(key, title) { screens.push([key, title]); }, setNavigationStack() {} });
  api.createNavigationListener()({ index: 0, routes: [{ name: 'Root', state: { routes: [{ name: 'Orders' }] } }] });
  assert.deepEqual(screens, [['orders', 'Orders']]);
});
