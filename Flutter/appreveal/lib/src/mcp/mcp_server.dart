// Embedded HTTP server for MCP Streamable HTTP transport.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'mcp_router.dart';

class MCPServer {
  HttpServer? _server;

  Future<void> start({int port = 0}) async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    // ignore: avoid_print
    print('[AppReveal] MCP server started on port ${_server!.port}');
    _serve();
  }

  void _serve() {
    _server?.listen(_handleRequest, onError: (_) {});
  }

  Future<void> _handleRequest(HttpRequest request) async {
    request.response.headers
      ..contentType = ContentType.json
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'POST, OPTIONS')
      ..set('Access-Control-Allow-Headers', 'Content-Type');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = 200;
      await request.response.close();
      return;
    }

    if (request.method != 'POST') {
      request.response.statusCode = 405;
      await request.response.close();
      return;
    }

    try {
      final body = await utf8.decoder.bind(request).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final response = await MCPRouter.shared.handle(json);
      request.response.statusCode = 200;
      request.response.write(jsonEncode(response));
    } catch (e) {
      request.response.statusCode = 400;
      request.response.write(jsonEncode({
        'jsonrpc': '2.0',
        'id': null,
        'error': {'code': -32700, 'message': 'Parse error: $e'},
      }));
    }

    await request.response.close();
  }

  int get port => _server?.port ?? 0;

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }
}
