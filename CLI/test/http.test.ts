import test from 'node:test';
import assert from 'node:assert/strict';
import { callTool, sendRequest } from '../src/mcp.js';
import { registerSessionUrl } from '../src/auth.js';
import { runCli, startApp, startServer, textResult } from './helpers/server.js';

for (const stringBatch of [false, true]) {
  test(`CLI authenticated snapshot/find/tap/type/state flows (${stringBatch ? 'Swift JSON text' : 'object'} batch)`, async (t) => {
    const app = await startApp({ stringBatch }); t.after(app.close);
    let result = await runCli(['snapshot', '--json'], app.sessionUrl);
    assert.equal(result.code, 0, result.stderr);
    const snapshot = JSON.parse(result.stdout)[0];
    assert.equal(snapshot.result.screen.screenKey, 'form.main');
    assert.equal(snapshot.result.elementCount, 7); // duplicate tree button merged
    assert.ok(!result.stdout.includes(app.token));
    assert.equal(snapshot.target.url, app.url);
    result = await runCli(['find', 'type', '--field', 'actions', '--json'], app.sessionUrl);
    assert.equal(JSON.parse(result.stdout)[0].result.matches[0].element.id, 'form.input');
    result = await runCli(['tap', 'Submit', '--exact', '--field', 'label', '--json'], app.sessionUrl);
    assert.equal(result.code, 0, result.stdout + result.stderr);
    assert.equal(app.state.taps, 1);
    result = await runCli(['type', 'hello', '--element', 'form.input', '--exact', '--json'], app.sessionUrl);
    assert.equal(result.code, 0, result.stdout + result.stderr);
    result = await runCli(['call', 'get_state', '--json'], app.sessionUrl);
    assert.equal(JSON.parse(result.stdout)[0].result.text, 'hello');
    for (const query of ['Duplicate', 'Disabled', 'Absent', ' ', 'Bad frame']) {
      result = await runCli(['tap', query, '--exact', '--field', 'label', '--json'], app.sessionUrl);
      assert.equal(result.code, 1, query);
      assert.equal(JSON.parse(result.stdout)[0].ok, false);
    }
    assert.equal(app.state.taps, 1);
    result = await runCli(['tap', 'form.submit', '--exact', '--json'], app.sessionUrl);
    assert.equal(result.code, 0);
    assert.equal(app.state.taps, 2); // recovered after failed queries
  });
}

test('tool errors and partial fleet errors fail the actual process without hiding successful targets', async (t) => {
  const app = await startApp(); t.after(app.close);
  for (const args of [['call', 'fail'], ['request', 'tools/call', '--params', '{"name":"fail"}']]) {
    const result = await runCli([...args, '--json'], app.sessionUrl);
    assert.equal(result.code, 1);
    assert.match(result.stdout, /Element unavailable/);
  }
  const unauth = await startApp(); t.after(unauth.close);
  const result = await runCli(['call', 'get_state', '--target', app.sessionUrl, '--target', unauth.url, '--json']);
  assert.equal(result.code, 1);
  assert.deepEqual(JSON.parse(result.stdout).map((item: { ok: boolean }) => item.ok).sort(), [false, true]);
  assert.ok(!result.stdout.includes(app.token));
  assert.ok(!result.stderr.includes(app.token));
});

test('auth rejection recovers with environment credentials and filters framework or OS', async (t) => {
  const app = await startApp(); t.after(app.close);
  assert.equal((await runCli(['tools', app.url, '--json'])).code, 1);
  for (const platform of ['flutter', 'windows']) {
    const result = await runCli(['inspect', app.url, '--platform', platform, '--json'], app.sessionUrl);
    assert.equal(result.code, 0, result.stdout + result.stderr);
    assert.ok(!result.stdout.includes(app.token));
  }
  assert.equal((await runCli(['inspect', app.url, '--platform', 'ios', '--json'], app.sessionUrl)).code, 1);
});

test('failed batch actions and failed focus never produce empty success or type into the wrong field', async (t) => {
  const failed = await startApp({ batchFailure: true }); t.after(failed.close);
  for (const args of [['snapshot'], ['tap', 'Submit']]) {
    const result = await runCli([...args, '--json'], failed.sessionUrl);
    assert.equal(result.code, 1);
    assert.match(result.stdout, /Inventory unavailable/);
  }
  const focus = await startApp({ focusFailure: true }); t.after(focus.close);
  const result = await runCli(['type', 'do not type', '--element', 'Anonymous field', '--exact', '--json'], focus.sessionUrl);
  assert.equal(result.code, 1);
  assert.equal(focus.state.text, '');
  assert.ok(!focus.requests.some((rpc) => rpc.params?.name === 'type_text'));
});

test('image and multi-part tool content survives CLI decoding', async (t) => {
  const image = { content: [{ type: 'image', mimeType: 'image/png', data: 'fixture-image-bytes' }, { type: 'text', text: '{"width":1}' }], structuredContent: { width: 1 } };
  const server = await startServer(() => image); t.after(server.close);
  const result = await runCli(['call', server.url, 'screenshot', '--json']);
  assert.equal(result.code, 0);
  assert.deepEqual(JSON.parse(result.stdout)[0].result, image);
});

test('isError, invalid JSON-RPC envelopes, IDs and error bodies are rejected', async (t) => {
  const cases: unknown[] = [null, [], {}, { jsonrpc: '2.0', id: 999, result: {} }, { jsonrpc: '2.0', id: 1, result: {}, error: {} }];
  for (const value of cases) {
    const server = await startServer((_rpc, _req, res) => res.end(JSON.stringify(value))); t.after(server.close);
    await assert.rejects(sendRequest(server.url, { method: 'tools/list', id: 1 }), /Invalid JSON-RPC/);
  }
  const error = await startServer(() => ({ ...textResult('Not actionable'), isError: true })); t.after(error.close);
  await assert.rejects(callTool(error.url, 'tap_element'), /Not actionable/);
  const malformed = await startServer((_rpc, _req, res) => res.end('not-json')); t.after(malformed.close);
  await assert.rejects(sendRequest(malformed.url, { method: 'tools/list' }), /Invalid JSON/);
});

test('redirects cannot forward a session token and slow bodies time out', async (t) => {
  let redirected = 0;
  const destination = await startServer(() => { redirected++; return {}; }); t.after(destination.close);
  const source = await startServer((_rpc, _req, res) => { res.writeHead(307, { Location: destination.url }); res.end(); }); t.after(source.close);
  await assert.rejects(callTool(`${source.url}?appreveal_session_token=redirect-fixture`, 'get_state'), /Fetch failed/);
  assert.equal(redirected, 0);
  const slow = await startServer((_rpc, _req, res) => { res.writeHead(200); res.write('{'); }); t.after(slow.close);
  await assert.rejects(sendRequest(slow.url, { method: 'tools/list', timeoutMs: 100 }), /after 100ms/);
});

test('server-echoed credentials are redacted from errors', async (t) => {
  const app = await startApp(); t.after(app.close);
  const server = await startServer((_rpc, req, res) => { res.statusCode = 403; res.end('x'.repeat(470) + req.headers.authorization); }); t.after(server.close);
  const result = await runCli(['tools', `${server.url}?appreveal_session_token=${app.token}`, '--json']);
  assert.equal(result.code, 1);
  assert.ok(!result.stdout.includes(app.token));
  assert.ok(!result.stdout.includes(app.token.slice(0, 12)));
  assert.match(result.stdout, /REDACTED/);
});

test('strict CLI numeric and object inputs reject malformed values', async () => {
  for (const value of ['2junk', '1.5', 'Infinity', '-1', '2147483648']) {
    assert.equal((await runCli(['discover', '--timeout', value])).code, 1);
  }
  assert.throws(() => registerSessionUrl('http://user:password@localhost/'), /userinfo/);
  assert.throws(() => registerSessionUrl('http://localhost/?appreveal_session_token='), /non-empty/);
});


test('explicit credentials override an old environment session for the same endpoint', async (t) => {
  const app = await startApp(); t.after(app.close);
  const result = await runCli(['tools', '--target', app.sessionUrl, '--json'], `${app.url}?appreveal_session_token=expired-fixture`);
  assert.equal(result.code, 0, result.stdout + result.stderr);
});

test('raw params must be an object and rejected input sends no request', async (t) => {
  const app = await startApp(); t.after(app.close);
  for (const params of ['[]', 'null', 'true']) {
    const result = await runCli(['request', 'tools/list', '--params', params, '--json'], app.sessionUrl);
    assert.equal(result.code, 1);
    assert.match(result.stdout, /Expected a JSON object/);
  }
  assert.equal(app.requests.length, 0);
});

test('batch payload errors and missing inventory cannot masquerade as an empty successful snapshot', async (t) => {
  for (const result of [{ results: [] }, { results: [{ tool: 'get_elements', result: '{"error":"No window"}' }] }]) {
    const server = await startServer(() => textResult(result)); t.after(server.close);
    const response = await runCli(['snapshot', server.url, '--json']);
    assert.equal(response.code, 1);
    assert.equal(JSON.parse(response.stdout)[0].ok, false);
  }
});

test('non-JSON-RPC HTTP failures and JSON-RPC errors fail text output too', async (t) => {
  const rpcError = await startServer((rpc, _req, res) => res.end(JSON.stringify({
    jsonrpc: '2.0', id: rpc.id, error: { code: -32602, message: 'Bad tool arguments' },
  }))); t.after(rpcError.close);
  let result = await runCli(['call', rpcError.url, 'tap_element']);
  assert.equal(result.code, 1);
  assert.match(result.stdout, /Bad tool arguments/);
  const httpError = await startServer((_rpc, _req, res) => { res.statusCode = 503; res.end('Unavailable'); }); t.after(httpError.close);
  result = await runCli(['tools', httpError.url]);
  assert.equal(result.code, 1);
  assert.match(result.stdout, /HTTP 503/);
});

test('the live probe reports failed state assertions as failures, without payloads', async (t) => {
  const { mkdtemp, writeFile, readFile, rm } = await import('node:fs/promises');
  const { tmpdir } = await import('node:os');
  const { join } = await import('node:path');
  const { execFile } = await import('node:child_process');
  const { promisify } = await import('node:util');
  const { fileURLToPath } = await import('node:url');
  const dir = await mkdtemp(join(tmpdir(), 'appreveal-cli-'));
  t.after(() => rm(dir, { recursive: true, force: true }));
  const app = await startApp(); t.after(app.close);
  await writeFile(join(dir, 'session.url'), app.sessionUrl, { mode: 0o600 });
  await writeFile(join(dir, 'plan.json'), JSON.stringify([{ label: 'state assertion', args: ['call', 'get_state'], expect: [{ path: [0, 'result', 'taps'], equals: 42 }] }]));
  const probe = fileURLToPath(new URL('../../scripts/verify-cli-mcp.mjs', import.meta.url));
  await assert.rejects(promisify(execFile)(process.execPath, [probe, '--session-file', join(dir, 'session.url'), '--plan', join(dir, 'plan.json'), '--report', join(dir, 'report.json')]), (error: unknown) => {
    const result = error as { code: number; stdout: string; stderr: string };
    assert.equal(result.code, 1);
    assert.ok(!result.stdout.includes('PASS state assertion'));
    assert.ok(!`${result.stdout}${result.stderr}`.includes(app.token));
    return true;
  });
  const report = JSON.parse(await readFile(join(dir, 'report.json'), 'utf8'));
  assert.equal(report.passed, false);
  assert.equal(report.failedStep, 'state assertion');
});


test('successful network details may contain an empty error field', async (t) => {
  const detail = { id: 'request-1', statusCode: 200, error: '' };
  const server = await startServer(() => textResult(detail)); t.after(server.close);
  const result = await runCli(['call', server.url, 'get_network_call_detail', '--arg', 'id=request-1', '--json']);
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.deepEqual(JSON.parse(result.stdout)[0].result, detail);
});

test('the live probe never echoes a malformed private session file', async (t) => {
  const { mkdtemp, writeFile, rm } = await import('node:fs/promises');
  const { tmpdir } = await import('node:os');
  const { join } = await import('node:path');
  const { execFile } = await import('node:child_process');
  const { promisify } = await import('node:util');
  const { fileURLToPath } = await import('node:url');
  const dir = await mkdtemp(join(tmpdir(), 'appreveal-cli-'));
  t.after(() => rm(dir, { recursive: true, force: true }));
  await writeFile(join(dir, 'session.url'), 'not-a-url?appreveal_session_token=private-fixture-value', { mode: 0o600 });
  const probe = fileURLToPath(new URL('../../scripts/verify-cli-mcp.mjs', import.meta.url));
  await assert.rejects(promisify(execFile)(process.execPath, [probe, '--session-file', join(dir, 'session.url')]), (error: unknown) => {
    const result = error as { code: number; stdout: string; stderr: string };
    assert.equal(result.code, 2);
    assert.ok(!`${result.stdout}${result.stderr}`.includes('private-fixture-value'));
    return true;
  });
});
