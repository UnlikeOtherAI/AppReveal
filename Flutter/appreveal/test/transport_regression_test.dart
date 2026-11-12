import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appreveal/src/mcp/mcp_router.dart';
import 'package:appreveal/src/mcp/mcp_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MCPServer server;
  late HttpClient client;
  setUp(() async {
    server = MCPServer();
    client = HttpClient();
    // Session URLs must not enter test logs.
    await runZoned(() => server.start(),
        zoneSpecification: ZoneSpecification(print: (_, __, ___, ____) {}));
    MCPRouter.shared.register(MCPToolDefinition(
      name: 'transport_probe',
      description: 'Probe',
      inputSchema: {
        'type': 'object',
        'properties': {
          'value': {'type': 'integer', 'minimum': 0}
        },
        'required': ['value']
      },
      handler: (args) async => args!['value'] == 0
          ? {'error': 'Expected failure'}
          : {'value': args['value']},
    ));
  });
  tearDown(() async {
    client.close(force: true);
    await server.stop();
  });
  Future<(int, Map<String, dynamic>?)> post(Object body,
      {String auth = 'header', String? origin}) async {
    var url = Uri.parse(server.url!);
    if (auth == 'query') {
      url = url.replace(
          queryParameters: {'appreveal_session_token': server.sessionToken!});
    }
    final request = await client.postUrl(url);
    if (auth == 'header') {
      request.headers.set('X-AppReveal-Session', server.sessionToken!);
    }
    if (auth == 'bearer') {
      request.headers.set('Authorization', 'Bearer ${server.sessionToken}');
    }
    if (auth == 'bad') request.headers.set('X-AppReveal-Session', 'invalid');
    if (origin != null) request.headers.set('Origin', origin);
    request.write(body is String ? body : jsonEncode(body));
    final response = await request.close();
    final data = await utf8.decoder.bind(response).join();
    return (
      response.statusCode,
      data.isEmpty ? null : jsonDecode(data) as Map<String, dynamic>
    );
  }

  Map<String, dynamic> call(dynamic args) => {
        'jsonrpc': '2.0',
        'id': 7,
        'method': 'tools/call',
        'params': {'name': 'transport_probe', 'arguments': args}
      };

  test('real HTTP requires auth and accepts all three session transports',
      () async {
    for (final auth in ['none', 'bad']) {
      expect((await post(call({'value': 1}), auth: auth)).$1, 401);
    }
    for (final auth in ['header', 'bearer', 'query']) {
      final result = await post(call({'value': 1}), auth: auth);
      expect(result.$1, 200);
      expect(result.$2!['result']['isError'], isNull);
    }
  });
  test('malformed requests, arguments and tool failures are distinguishable',
      () async {
    expect((await post('{')).$2!['error']['code'], -32700);
    expect((await post([])).$2!['error']['code'], -32600);
    expect(
        (await post({'jsonrpc': '2.0', 'id': 7, 'method': 4})).$2!['error']
            ['code'],
        -32600);
    for (final args in [
      [],
      {'value': 'wrong'},
      {'value': -1},
      <String, dynamic>{}
    ]) {
      expect((await post(call(args))).$2!['error']['code'], -32602);
    }
    expect((await post(call({'value': 0}))).$2!['result']['isError'], true);
    expect((await post(call({'value': 1}))).$2!['result']['isError'], isNull);
  });
  test('notifications have no body and ping returns an empty result', () async {
    final notification =
        await post({'jsonrpc': '2.0', 'method': 'notifications/initialized'});
    expect(notification.$1, 204);
    expect(notification.$2, isNull);
    expect(
        (await post({'jsonrpc': '2.0', 'id': 8, 'method': 'ping'}))
            .$2!['result'],
        isEmpty);
  });
  test('origin validation rejects lookalikes and accepts actual loopback',
      () async {
    for (final origin in [
      'https://attacker.invalid',
      'http://127.attacker.invalid',
      'http://localhost@attacker.invalid'
    ]) {
      expect((await post(call({'value': 1}), origin: origin)).$1, 403);
    }
    for (final origin in [
      'http://127.0.0.1:8080',
      'http://localhost:3000',
      'http://[::1]:8080'
    ]) {
      expect((await post(call({'value': 1}), origin: origin)).$1, 200);
    }
  });
}
