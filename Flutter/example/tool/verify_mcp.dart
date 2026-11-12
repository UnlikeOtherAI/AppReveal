// Run with: flutter run -d windows -t tool/verify_mcp.dart
// Uses the real example, HTTP transport and pointer/text actions. No mocked APIs.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appreveal/appreveal.dart';
import 'package:flutter/widgets.dart';
import 'package:appreveal_example/main.dart' as example;

void main() {
  runZoned(() {
    example.main();
    unawaited(_verify());
  }, zoneSpecification: ZoneSpecification(print: (self, parent, zone, message) {
    // The ordinary app prints its session URL for local setup. This runner
    // keeps the token in memory and never writes it to verification evidence.
    if (!message.contains('appreveal_session_token='))
      parent.print(zone, message);
  }));
}

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> _verify() async {
  final checks = <String>[];
  final client = HttpClient();
  var nextId = 1;
  String? failure;
  Future<Map<String, dynamic>> rpc(String method,
      {Map<String, dynamic>? params, bool authorized = true}) async {
    final request = await client.postUrl(Uri.parse(AppReveal.url!));
    if (authorized)
      request.headers.set('X-AppReveal-Session', AppReveal.sessionToken!);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({
      'jsonrpc': '2.0',
      'id': nextId++,
      'method': method,
      if (params != null) 'params': params
    }));
    final response = await request.close();
    final body = jsonDecode(await utf8.decoder.bind(response).join())
        as Map<String, dynamic>;
    check(response.statusCode == (authorized ? 200 : 401),
        'Unexpected HTTP status');
    return body;
  }

  Future<Map<String, dynamic>> tool(String name,
      [Map<String, dynamic> args = const {}, bool error = false]) async {
    final response =
        await rpc('tools/call', params: {'name': name, 'arguments': args});
    check(!response.containsKey('error'), '$name returned a protocol error');
    final result = response['result'] as Map<String, dynamic>;
    check((result['isError'] == true) == error,
        '$name(${args['element_id'] ?? ''}) returned unexpected tool status: ${result['isError'] == true ? result['content'] : 'expected error'}');
    final content = result['content'] as List;
    if (content.first['type'] == 'image') {
      final bytes = base64Decode(content.first['data'] as String);
      check(bytes.length > 100, '$name returned an empty image');
      return result['structuredContent'] as Map<String, dynamic>;
    }
    return jsonDecode(content.first['text'] as String) as Map<String, dynamic>;
  }

  Future<void> screen(String expected) async {
    for (var i = 0; i < 60; i++) {
      if ((await tool('get_screen'))['screenKey'] == expected) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('Screen did not become $expected');
  }

  try {
    for (var i = 0; i < 100 && AppReveal.url == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    check(AppReveal.url != null, 'MCP server did not start');
    await WidgetsBinding.instance.endOfFrame;
    await rpc('initialize', authorized: false);
    await rpc('initialize');
    final listed = (await rpc('tools/list'))['result']['tools'] as List;
    check(listed.length >= 44, 'Advertised tools missing');
    checks.add('unauthenticated rejection, initialize and tools/list');
    await screen('auth.login');
    final elements = (await tool('get_elements'))['elements'] as List;
    check(elements.any((e) => e['id'] == 'login.email'),
        'Email absent from inventory');
    check(
        ((await tool('get_view_tree', {'max_depth': 80}))['views'] as List)
            .isNotEmpty,
        'Empty widget tree');
    await tool('type_text',
        {'element_id': 'login.email', 'text': 'first@example.test'});
    await tool('type_text', {'element_id': 'missing', 'text': 'wrong'}, true);
    await tool('clear_text', {'element_id': 'login.email'});
    await tool('type_text',
        {'element_id': 'login.email', 'text': 'flutter@example.test'});
    await tool(
        'type_text', {'element_id': 'login.password', 'text': 'example-only'});
    final crop = await tool('screenshot', {'element_id': 'login.submit'});
    check((crop['width'] as num) > 0 && (crop['height'] as num) > 0 && (crop['height'] as num) < 200,
        'Invalid screenshot crop');
    await tool('tap_text', {'text': 'Sign In'});
    await screen('catalog.list');
    final state = await tool('get_state');
    check(
        state['isLoggedIn'] == true &&
            state['userEmail'] == 'flutter@example.test',
        'Typing/login did not update state');
    check((await tool('get_navigation_stack'))['currentRoute'] == '/main',
        'Navigation provider is stale');
    checks.add(
        'inventory, tree, targeted typing, missing-target failure, clear, element screenshot and login state');
    await tool('scroll', {'container_id': 'catalog.list', 'direction': 'down'});
    await tool('scroll_to_element', {'element_id': 'catalog.item.p1'});
    await tool('tap_element', {'element_id': 'catalog.item.p1'});
    await screen('catalog.detail');
    final productElements = (await tool('get_elements'))['elements'] as List;
    final cartButton = productElements.firstWhere((e) => e['id'] == 'product.add_to_cart') as Map;
    final frame = (cartButton['frame'] as String).split(',').map(double.parse).toList();
    await tool('tap_point', {'x': frame[0] + frame[2] / 2, 'y': frame[1] + frame[3] / 2});
    check((await tool('get_state'))['cartItemCount'] == 1,
        'Cart mutation missing');
    await tool('dismiss_modal', {}, true);
    await tool('navigate_back');
    await screen('catalog.list');
    checks.add(
        'scroll, scroll-to, product tap, state mutation, wrong-modal rejection and back identity');
    await tool('select_tab', {'index': 2});
    await screen('cart.main');
    // The product snackbar temporarily covers Checkout. Let it leave as it
    // would during normal use; covered targets correctly reject pointer taps.
    await Future<void>.delayed(const Duration(seconds: 4));
    await tool('tap_element', {'element_id': 'cart.checkout'});
    await Future<void>.delayed(const Duration(milliseconds: 400));
    check(
        ((await tool('get_navigation_stack'))['presentedModals'] as List)
            .isNotEmpty,
        'Dialog missing from navigation');
    await tool('dismiss_modal');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    check(
        ((await tool('get_navigation_stack'))['presentedModals'] as List)
            .isEmpty,
        'Dialog was not dismissed');
    await tool('select_tab', {'index': 3});
    await screen('profile.main');
    await tool('tap_element', {'element_id': 'profile.edit'});
    await screen('profile.edit');
    await tool('clear_text', {'element_id': 'edit_profile.name'});
    await tool('type_text',
        {'element_id': 'edit_profile.name', 'text': 'Flutter MCP'});
    await tool('tap_element', {'element_id': 'edit_profile.save'});
    await screen('profile.main');
    check((await tool('get_state'))['userName'] == 'Flutter MCP',
        'Profile save did not persist');
    checks.add('tab selection, checkout modal lifecycle and profile edit/save');
    await tool('get_feature_flags');
    check(((await tool('get_network_calls'))['calls'] as List).isNotEmpty,
        'Example network captures missing');
    await tool('get_logs');
    check(((await tool('get_recent_errors'))['errors'] as List).isEmpty,
        'Unexpected Flutter errors');
    await tool('launch_context');
    final device = await tool('device_info');
    check(device['frameworkType'] == 'flutter', 'Wrong runtime');
    check(((await tool('get_webviews'))['webviews'] as List).isEmpty,
        'Unexpected WebView');
    await tool('web_click', {'selector': '#missing'}, true);
    final batch = await tool(
        'batch',
        {
          'stop_on_error': true,
          'actions': [
            {
              'tool': 'tap_element',
              'arguments': {'element_id': 'missing'}
            },
            {
              'tool': 'select_tab',
              'arguments': {'index': 0}
            },
          ]
        },
        true);
    check(batch['count'] == 1, 'Batch did not stop on tool error');
    await screen('profile.main');
    final full = await tool('screenshot', {'format': 'jpeg'});
    check(full['format'] == 'jpeg', 'JPEG response mismatch');
    checks.add(
        'flags, diagnostics, network captures, runtime, WebView absence, batch recovery and full JPEG');
  } catch (e) {
    failure = e.toString();
  } finally {
    client.close(force: true);
    await AppReveal.stop();
  }
  final report = {
    'passed': failure == null,
    'checks': checks,
    if (failure != null) 'error': failure,
    'platform': Platform.operatingSystem,
    'sourceRevision': const String.fromEnvironment('APPREVEAL_SOURCE_REVISION', defaultValue: 'working-tree'),
    'webviewLimitation':
        'webview_flutter has no Windows backend; DOM payloads are checked separately'
  };
  const evidence = String.fromEnvironment('APPREVEAL_EVIDENCE_DIR');
  if (evidence.isNotEmpty) {
    final directory = Directory(evidence)..createSync(recursive: true);
    File('${directory.path}/mcp-live.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
  }
  // ignore: avoid_print
  print(jsonEncode(report));
  exit(failure == null ? 0 : 1);
}
