#!/usr/bin/env node
// Drive the built CLI against an existing app. Never print captured tool payloads or credentials.
import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';

const options = new Map();
for (let i = 2; i < process.argv.length; i += 2) options.set(process.argv[i], process.argv[i + 1]);
if (!options.get('--session-file')) {
  process.stderr.write('Usage: node scripts/verify-cli-mcp.mjs --session-file <private-file> [--host <LAN-IP>] [--plan <json-file>] [--report <json-file>]\n');
  process.exit(2);
}
const report = { kind: 'live-cli-http', timestamp: new Date().toISOString(), host: process.platform, steps: [] };
const cli = fileURLToPath(new URL('../CLI/dist/index.js', import.meta.url));
let url, secret, endpoint;
try {
  url = new URL((await readFile(options.get('--session-file'), 'utf8')).trim());
  if (options.get('--host')) url.hostname = options.get('--host');
  secret = url.searchParams.get('appreveal_session_token');
  assert.ok(secret);
  endpoint = new URL(url); endpoint.searchParams.delete('appreveal_session_token');
} catch {
  process.stderr.write('Invalid private session file or endpoint. Contents withheld.\n');
  process.exit(2);
}

async function command(label, args, { authorized = true, expectFailure = false, expect = [], validate = () => {} } = {}) {
  report.currentStep = label;
  const env = { ...process.env };
  delete env.APPREVEAL_SESSION_URL;
  if (authorized) env.APPREVEAL_SESSION_URL = url.toString();
  let code = 0, stdout = '', stderr = '';
  try {
    ({ stdout, stderr } = await promisify(execFile)(process.execPath, [cli, ...args, '--json'], { env, timeout: 60_000, maxBuffer: 32 * 1024 * 1024 }));
  } catch (error) {
    code = error.code; stdout = error.stdout ?? ''; stderr = error.stderr ?? '';
  }
  assert.ok(!`${stdout}${stderr}`.includes(secret), `${label}: credential leaked`);
  assert.equal(code === 0, !expectFailure, `${label}: unexpected exit status (payload withheld)`);
  const data = JSON.parse(stdout);
  assert.ok(Array.isArray(data), `${label}: fleet JSON expected`);
  assert.ok(data.length > 0, `${label}: missing target`);
  assert.equal(data.every((target) => target.ok), !expectFailure, `${label}: incorrect target status`);
  for (const expectation of expect) {
    let value = data;
    for (const key of expectation.path) value = value?.[key];
    assert.deepEqual(value, expectation.equals, `${label}: resulting state did not match`);
  }
  validate(data);
  report.steps.push({ label, passed: true, exitCode: code });
  process.stdout.write(`PASS ${label}\n`);
  return data;
}

try {
  await command('unauthenticated request rejected', ['tools', endpoint.toString()], {
    authorized: false, expectFailure: true, validate: (data) => assert.match(data[0].error, /HTTP 401/),
  });
  await command('authenticated inspection', ['inspect']);
  const tools = await command('tool inventory', ['tools'], { validate: (data) => {
    assert.ok(data[0].result.tools.some((tool) => tool.name === 'launch_context'));
    for (const tool of data[0].result.tools) {
      assert.equal(tool.inputSchema.type, 'object');
      for (const key of tool.inputSchema.required ?? []) assert.ok(Object.hasOwn(tool.inputSchema.properties ?? {}, key));
    }
  } });
  const names = tools[0].result.tools.map((tool) => tool.name);
  if (['batch', 'get_screen', 'get_elements', 'get_view_tree'].every((name) => names.includes(name))) {
    const snapshot = await command('screen and element snapshot', ['snapshot'], {
      validate: (data) => assert.ok(Number.isInteger(data[0].result.elementCount)),
    });
    report.elementCount = snapshot[0].result.elementCount;
  }
  await command('unknown tool rejected', ['call', '__appreveal_cli_missing_tool__'], { expectFailure: true });
  await command('recovery after rejection', ['call', 'launch_context']);
  if (options.get('--plan')) {
    const plan = JSON.parse(await readFile(options.get('--plan'), 'utf8'));
    for (const step of plan) {
      await command(step.label, step.args, { expectFailure: Boolean(step.expectFailure), expect: step.expect ?? [] });
    }
  }
  report.passed = true;
} catch {
  // Assertions can include payloads. Only emit step labels and a bounded failure summary.
  report.passed = false;
  report.failedStep = report.currentStep;
  process.stderr.write('FAIL live CLI verification; inspect the last completed step. Payloads withheld.\n');
  process.exitCode = 1;
} finally {
  delete report.currentStep;
  if (options.get('--report')) await writeFile(options.get('--report'), `${JSON.stringify(report, null, 2)}\n`);
}
