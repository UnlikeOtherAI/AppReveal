#!/usr/bin/env python3
"""Authenticated example-app checks; session credentials stay in process memory.
Build/install the debug APK first. Run with ANDROID_HOME and ANDROID_SERIAL.
Optional --screenshots checks PNG/JPEG in memory (two captures, no files).
"""
import base64
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

adb = os.path.join(os.environ['ANDROID_HOME'], 'platform-tools', 'adb')
serial = os.environ.get('ANDROID_SERIAL', 'emulator-5554')
package = 'com.appreveal.example'
endpoint = token = None
calls = 0

def device(*args):
    return subprocess.check_output([adb, '-s', serial, *args], text=True)

def start(activity):
    global endpoint, token
    device('shell', 'am', 'force-stop', package)
    device('shell', 'am', 'start', '-W', '-n', package + '/' + activity)
    for _ in range(40):
        entries = re.findall(r'Session URL: http://127\.0\.0\.1:(\d+)/\?appreveal_session_token=(\w+)', device('logcat', '-d', '-s', 'AppReveal:I', '*:S'))
        if entries:
            port, token = entries[-1]
            endpoint = 'http://127.0.0.1:' + port + '/'
            device('forward', 'tcp:' + port, 'tcp:' + port)
            try:
                rpc('initialize')
                time.sleep(0.4)
                return
            except (urllib.error.URLError, ConnectionError):
                pass
        time.sleep(0.2)
    raise AssertionError('No active MCP session')

def rpc(method, params=None, auth=True):
    headers = {'Content-Type': 'application/json'}
    if auth:
        headers['Authorization'] = 'Bearer ' + token
    request = urllib.request.Request(endpoint, json.dumps({'jsonrpc': '2.0', 'id': 1, 'method': method, 'params': params or {}}).encode(), headers)
    with urllib.request.urlopen(request, timeout=15) as response:
        return json.load(response)

def call(name, args=None, error=False):
    global calls
    response = rpc('tools/call', {'name': name, 'arguments': args or {}})
    calls += 1
    if 'error' in response:
        assert error, (name, response['error'])
        return response
    result = response['result']
    if name == 'screenshot' and not error:
        return result
    payload = json.loads(result['content'][0]['text'])
    if error:
        assert result.get('isError') or 'error' in payload, (name, payload)
    else:
        assert not result.get('isError') and not payload.get('error'), (name, payload)
    return payload

def elements():
    return call('get_elements')['elements']

def element(id):
    return next(e for e in elements() if e['id'] == id)

def wait_for(predicate):
    for _ in range(40):
        if predicate():
            return
        time.sleep(0.15)
    raise AssertionError('State did not reconcile')

def web(js):
    return call('web_evaluate', {'javascript': js})['result']

start('.MainActivity')
try:
    rpc('tools/list', auth=False)
    raise AssertionError('Unauthenticated MCP accepted')
except urllib.error.HTTPError as error:
    assert error.code == 401
assert len(rpc('tools/list')['result']['tools']) >= 40
assert call('get_screen')['screenKey'] == 'login'
call('get_view_tree')
call('tap_point', {'x': -100, 'y': 0}, error=True)
call('tap_element', {'element_id': 'does.not.exist'}, error=True)
call('tap_text', {'text': 'Log In', 'occurrence': -1}, error=True)
call('type_text', {'element_id': 'emailField', 'text': 'invalid'})
assert element('emailField')['value'] == 'invalid'
call('tap_element', {'element_id': 'loginButton'})
wait_for(lambda: any(e['id'] == 'errorLabel' and 'Invalid' in e['value'] for e in elements()))
call('clear_text', {'element_id': 'emailField'})
call('type_text', {'element_id': 'emailField', 'text': 'test@example.com'})
call('type_text', {'element_id': 'passwordField', 'text': 'example-only'})
call('tap_element', {'element_id': 'loginButton'})
wait_for(lambda: call('get_screen')['screenKey'] != 'login')
for name in ['get_state', 'get_navigation_stack', 'get_feature_flags', 'get_recent_errors', 'launch_context', 'device_info', 'get_logs']:
    call(name)
call('dismiss_modal', error=True)
network = call('get_network_calls')['calls']
assert network
call('get_network_call_detail', {'id': network[0]['id']})
call('get_network_call_detail', {'id': 'missing'}, error=True)
call('select_tab', {'index': 99}, error=True)
call('select_tab', {'index': 3})
wait_for(lambda: any(e['id'] == 'darkModeSwitch' for e in elements()))
toggle = element('darkModeSwitch')
assert toggle['type'] == 'toggle' and toggle['value'] in ['true', 'false']
call('tap_element', {'element_id': 'darkModeSwitch'})
assert element('darkModeSwitch')['value'] != toggle['value']
call('scroll', {'direction': 'down'})
call('scroll', {'direction': 'up'})
call('scroll_to_element', {'element_id': 'deleteAccountButton'})
wait_for(lambda: element('deleteAccountButton')['visible'] == 'true')
call('scroll_to_element', {'element_id': 'tapCalibrationButton'})
call('tap_element', {'element_id': 'tapCalibrationButton'})
wait_for(lambda: any(e['id'] == 'calibration_target' for e in elements()))
x,y,w,h = map(float, element('calibration_target')['frame'].split(','))
call('tap_point', {'x': x+w/2, 'y': y+h/2})
wait_for(lambda: any(e['value'] == 'Target taps: 1' for e in elements()))
if os.environ.get('APPREVEAL_EVIDENCE_DIR'):
    os.makedirs(os.environ['APPREVEAL_EVIDENCE_DIR'], exist_ok=True)
    capture = call('screenshot', {'format': 'png'})
    with open(os.path.join(os.environ['APPREVEAL_EVIDENCE_DIR'], 'android-calibration-after.png'), 'wb') as image:
        image.write(base64.b64decode(capture['content'][0]['data']))
call('navigate_back')
call('select_tab', {'index': 4})
wait_for(lambda: call('get_webviews')['count'] == 1)
wait_for(lambda: web('!!document.body && document.body.children.length > 0') == 'true')
for name in ['get_dom_tree', 'get_dom_interactive', 'get_dom_links', 'get_dom_text', 'get_dom_forms', 'get_dom_headings', 'get_dom_images', 'get_dom_tables', 'get_dom_summary']:
    call(name)
# A repeatable in-page test fixture exercises DOM input events and error paths.
web("document.body.innerHTML = '<h1>Fixture</h1><input id=field><input id=locked readonly value=original><button id=disabled disabled>Disabled</button><button id=go>Go</button><input type=checkbox id=check><select id=choice><option value=a>A</option><option value=b>B</option></select><p id=result>idle</p>'; document.querySelector('#go').onclick=()=>document.querySelector('#result').textContent=document.querySelector('#field').value; 'ready'")
call('query_dom', {'selector': '#field'})
call('find_dom_text', {'text': 'Fixture'})
text = 'literal \\n \\t "quote" é'
call('web_type', {'selector': '#field', 'text': text, 'clear': True})
assert web("document.querySelector('#field').value") == text
call('web_click', {'selector': '#go'})
assert web("document.querySelector('#result').textContent") == text
call('web_type', {'selector': '#locked', 'text': 'changed'}, error=True)
assert web("document.querySelector('#locked').value") == 'original'
call('web_click', {'selector': '#disabled'}, error=True)
call('web_toggle', {'selector': '#check', 'checked': True})
assert web("document.querySelector('#check').checked") == 'true'
call('web_toggle', {'selector': '#go', 'checked': True}, error=True)
call('web_select', {'selector': '#choice', 'value': 'b'})
assert web("document.querySelector('#choice').value") == 'b'
call('web_select', {'selector': '#choice', 'value': 'missing'}, error=True)
assert web("document.querySelector('#choice').value") == 'b'
call('query_dom', {'selector': '['}, error=True)
call('web_evaluate', {'javascript': "throw new Error('expected failure')"}, error=True)
assert web("'recovered'") == 'recovered'
call('web_scroll_to', {'selector': '#result'})
call('web_back', error=True)
call('web_forward', error=True)
call('web_navigate', {'url': 'about:blank'})
call('get_dom_tree', {'root': '#appreveal-missing-root'}, error=True)
call('get_dom_tree', {'root': 'body'})
call('get_dom_tree', {'webview_id': 'missing'}, error=True)
result = call('batch', {'stop_on_error': True, 'actions': [{'tool': 'clear_text', 'arguments': {'element_id': 'missing'}}, {'tool': 'get_state'}]}, error=True)
assert result['count'] == 1
call('open_deeplink', {'url': 'appreveal://settings'})

start('.screens.ComposeActivity')
assert call('get_screen')['frameworkType'] == 'compose'
call('clear_text', {'element_id': 'compose.message'})
call('type_text', {'element_id': 'compose.message', 'text': 'hello compose'})
assert element('compose.message')['value'] == 'hello compose'
call('tap_text', {'text': 'Send a message'})
wait_for(lambda: any(e['label'] == 'Send count: 1' for e in elements()))
call('tap_element', {'element_id': 'duplicate_action_1'})
wait_for(lambda: any(e['label'] == 'Duplicate result: second' for e in elements()))
call('tap_element', {'element_id': 'compose.message'})
call('type_text', {'text': ' focused'})
assert element('compose.message')['value'] == 'hello compose focused'
call('clear_text', {'element_id': 'compose.message'})
assert element('compose.message')['value'] == ''
assert 'scroll' in element('compose.scroll')['actions']
# Force a small viewport so the scroll must change the visible content, then
# restore the emulator's previous override even if an assertion fails.
size_info = device('shell', 'wm', 'size')
old_override = re.search(r'Override size: (\d+x\d+)', size_info)
try:
    device('shell', 'wm', 'size', '720x900')
    time.sleep(0.8)
    before = {e['id']: e['frame'] for e in elements()}
    call('scroll', {'container_id': 'compose.scroll', 'direction': 'down'})
    wait_for(lambda: {e['id']: e['frame'] for e in elements()} != before)
    call('scroll', {'container_id': 'compose.scroll', 'direction': 'up'})
finally:
    device('shell', 'wm', 'size', old_override.group(1) if old_override else 'reset')
    time.sleep(0.8)
call('scroll', {'direction': 'diagonal'}, error=True)
if '--screenshots' in sys.argv:
    for fmt, magic in [('png', b'\x89PNG\r\n\x1a\n'), ('jpeg', b'\xff\xd8')]:
        result = call('screenshot', {'format': fmt})
        assert result['content'][0]['type'] == 'image'
        assert base64.b64decode(result['content'][0]['data']).startswith(magic)
        assert result['structuredContent']['width'] > 0
    result = call('screenshot', {'element_id': 'compose.message', 'format': 'png'})
    assert base64.b64decode(result['content'][0]['data']).startswith(b'\x89PNG')
    assert result['structuredContent']['width'] == int(float(element('compose.message')['frame'].split(',')[2]))
    call('screenshot', {'format': 'unsupported'}, error=True)
print(f'PASS: {calls} authenticated tool calls; Android API {device("shell", "getprop", "ro.build.version.sdk").strip()}; revision {subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()}')
