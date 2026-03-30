import test from 'node:test';
import assert from 'node:assert/strict';
import { extractCodes, normalizeUrl } from '../src/discovery.js';
import { buildArguments, parseJsonObject, parseLooseValue } from '../src/mcp.js';

test('normalizeUrl keeps explicit urls and appends trailing slash', () => {
  assert.equal(normalizeUrl('http://192.168.1.24:49152'), 'http://192.168.1.24:49152/');
  assert.equal(normalizeUrl('https://example.local/path'), 'https://example.local/path');
});

test('extractCodes keeps code-like txt fields and probe version codes', () => {
  assert.deepEqual(
    extractCodes(
      { bundleId: 'com.example.app', pin: '1234', token: 'abcd' },
      { build: '12', versionCode: 34 },
    ),
    { pin: '1234', token: 'abcd', build: '12', versionCode: '34' },
  );
});

test('parseJsonObject requires a json object', () => {
  assert.deepEqual(parseJsonObject('{"limit": 10, "clear": true}'), { limit: 10, clear: true });
  assert.throws(() => parseJsonObject('["bad"]'));
});

test('parseLooseValue parses booleans, numbers, null, and nested json', () => {
  assert.equal(parseLooseValue('true'), true);
  assert.equal(parseLooseValue('12.5'), 12.5);
  assert.equal(parseLooseValue('null'), null);
  assert.deepEqual(parseLooseValue('{"max_depth":3}'), { max_depth: 3 });
});

test('buildArguments merges json args and repeated key value args', () => {
  assert.deepEqual(
    buildArguments('{"text":"hello"}', ['clear=true', 'count=2']),
    { text: 'hello', clear: true, count: 2 },
  );
});
