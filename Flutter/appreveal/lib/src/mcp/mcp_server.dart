// Embedded HTTP server for MCP Streamable HTTP transport.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'mcp_router.dart';

class MCPServer {
  static const _sessionTokenQueryName = 'appreveal_session_token';
  static const _sessionTokenHeaderName = 'x-appreveal-session';

  HttpServer? _server;
  String? _sessionToken;

  Future<void> start({int port = 0, String? sessionToken}) async {
    if (_server != null) {
      // ignore: avoid_print
      print('[AppReveal] start ignored; already running at $sessionUrl');
      return;
    }

    _sessionToken =
        sessionToken?.isNotEmpty == true ? sessionToken : _makeSessionToken();
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    // ignore: avoid_print
    print('[AppReveal] MCP server started on port ${_server!.port}');
    // ignore: avoid_print
    print('[AppReveal] Session URL: $sessionUrl');
    // ignore: avoid_print
    print(
      '[AppReveal] Clients must include Authorization: Bearer <token> or X-AppReveal-Session.',
    );
    _serve();
  }

  void _serve() {
    _server?.listen(_handleRequest, onError: (_) {});
  }

  Future<void> _handleRequest(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    _applyCors(request);

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    if (request.method == 'GET' && request.uri.path == '/health') {
      request.response.statusCode = HttpStatus.ok;
      request.response.write(jsonEncode({
        'status': 'ok',
        'port': port,
        'auth': 'session-token',
        'discovery': 'dart-mdns',
      }));
      await request.response.close();
      return;
    }

    if (request.method != 'POST') {
      request.response.statusCode = 405;
      await request.response.close();
      return;
    }

    if (!_isAuthorized(request)) {
      request.response.statusCode = HttpStatus.unauthorized;
      request.response.write(jsonEncode({
        'jsonrpc': '2.0',
        'id': null,
        'error': {'code': -32001, 'message': 'Unauthorized'},
      }));
      await request.response.close();
      return;
    }

    try {
      final body = await utf8.decoder.bind(request).join();
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('JSON-RPC payload must be an object');
      }
      final expectsResponse = decoded.containsKey('id');
      final response = await MCPRouter.shared.handle(decoded);
      if (!expectsResponse) {
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
        return;
      }
      request.response.statusCode = 200;
      request.response.write(jsonEncode(response));
    } catch (e) {
      request.response.statusCode = 400;
      request.response.write(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': null,
          'error': {'code': -32700, 'message': 'Parse error: $e'},
        }),
      );
    }

    await request.response.close();
  }

  int get port => _server?.port ?? 0;

  String? get sessionToken => _sessionToken;

  String? get url => port == 0 ? null : 'http://127.0.0.1:$port/';

  String? get sessionUrl {
    final baseUrl = url;
    final token = _sessionToken;
    if (baseUrl == null || token == null) return null;
    return '$baseUrl?$_sessionTokenQueryName=${Uri.encodeQueryComponent(token)}';
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _sessionToken = null;
  }

  bool _isAuthorized(HttpRequest request) {
    final expected = _sessionToken;
    if (expected == null) return false;

    final queryToken = request.uri.queryParameters[_sessionTokenQueryName];
    if (_constantTimeEquals(queryToken, expected)) return true;

    final headerToken = request.headers.value(_sessionTokenHeaderName);
    if (_constantTimeEquals(headerToken, expected)) return true;

    final bearerToken = _readBearerToken(request.headers.value('authorization'));
    return _constantTimeEquals(bearerToken, expected);
  }

  String? _readBearerToken(String? value) {
    const prefix = 'Bearer ';
    if (value == null ||
        value.length <= prefix.length ||
        !value.toLowerCase().startsWith(prefix.toLowerCase())) {
      return null;
    }
    return value.substring(prefix.length).trim();
  }

  bool _constantTimeEquals(String? actual, String expected) {
    if (actual == null) return false;
    final actualBytes = utf8.encode(actual);
    final expectedBytes = utf8.encode(expected);
    if (actualBytes.length != expectedBytes.length) return false;

    var diff = 0;
    for (var index = 0; index < actualBytes.length; index++) {
      diff |= actualBytes[index] ^ expectedBytes[index];
    }
    return diff == 0;
  }

  void _applyCors(HttpRequest request) {
    final origin = request.headers.value('origin');
    if (origin == null || !_isLoopbackOrigin(origin)) return;

    request.response.headers
      ..set('Access-Control-Allow-Origin', origin)
      ..set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
      ..set(
        'Access-Control-Allow-Headers',
        'Authorization, Content-Type, X-AppReveal-Session',
      )
      ..set('Vary', 'Origin');
  }

  bool _isLoopbackOrigin(String origin) {
    final uri = Uri.tryParse(origin);
    final host = uri?.host.toLowerCase().replaceAll(RegExp(r'\.$'), '');
    return host != null &&
        (uri!.scheme == 'http' || uri.scheme == 'https') &&
        (host == 'localhost' ||
            host.endsWith('.localhost') ||
            host == '127.0.0.1' ||
            host.startsWith('127.') ||
            host == '::1');
  }

  String _makeSessionToken() {
    final random = Random.secure();
    return List.generate(
      32,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}
