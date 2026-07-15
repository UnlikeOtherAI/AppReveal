// MCP tool registry and JSON-RPC 2.0 dispatch.

import 'dart:convert';

typedef MCPToolHandler = Future<dynamic> Function(Map<String, dynamic>? params);

enum MCPToolOutputKind { jsonText, image }

class MCPToolDefinition {
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;
  final MCPToolOutputKind outputKind;
  final MCPToolHandler handler;

  const MCPToolDefinition({
    required this.name,
    required this.description,
    required this.inputSchema,
    this.outputKind = MCPToolOutputKind.jsonText,
    required this.handler,
  });
}

class MCPRouter {
  static final shared = MCPRouter._();
  MCPRouter._();

  final _tools = <String, MCPToolDefinition>{};

  void register(MCPToolDefinition tool) {
    _tools[tool.name] = tool;
  }

  MCPToolDefinition? tool(String name) => _tools[name];

  Future<Map<String, dynamic>> handle(Map<String, dynamic> request) async {
    final id = request['id'];
    final method = request['method'] as String? ?? '';

    switch (method) {
      case 'initialize':
        return _response(id, {
          'protocolVersion': '2025-06-18',
          'capabilities': {'tools': {}},
          'serverInfo': {'name': 'AppReveal', 'version': '0.10.1'},
        });

      case 'tools/list':
        final toolList = _tools.values
            .map((t) => {
                  'name': t.name,
                  'description': t.description,
                  'inputSchema': t.inputSchema,
                })
            .toList();
        return _response(id, {'tools': toolList});

      case 'tools/call':
        final params = request['params'] as Map<String, dynamic>?;
        final toolName = params?['name'] as String?;
        if (toolName == null) {
          return _error(id, -32602, 'Missing tool name');
        }
        final definition = _tools[toolName];
        if (definition == null) {
          return _error(id, -32601, 'Tool not found: $toolName');
        }
        try {
          final args = params?['arguments'] as Map<String, dynamic>?;
          final result = await definition.handler(args);
          return _response(id, _toolCallResult(result, definition.outputKind));
        } catch (e) {
          return _error(id, -32603, e.toString());
        }

      default:
        return _error(id, -32601, 'Method not found: $method');
    }
  }

  static Map<String, dynamic> _response(dynamic id, dynamic result) => {
        'jsonrpc': '2.0',
        'id': id,
        'result': result,
      };

  static Map<String, dynamic> _error(dynamic id, int code, String message) => {
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': code, 'message': message},
      };

  static Map<String, dynamic> _toolCallResult(
    dynamic result,
    MCPToolOutputKind outputKind,
  ) {
    return switch (outputKind) {
      MCPToolOutputKind.jsonText => _textToolCallResult(result),
      MCPToolOutputKind.image => _imageToolCallResult(result),
    };
  }

  static Map<String, dynamic> _textToolCallResult(
    dynamic result, {
    bool isError = false,
  }) {
    final response = <String, dynamic>{
      'content': [
        {'type': 'text', 'text': jsonEncode(result)},
      ],
    };
    if (isError) response['isError'] = true;
    return response;
  }

  static Map<String, dynamic> _imageToolCallResult(dynamic result) {
    if (result is! Map<String, dynamic>) {
      return _textToolCallResult(
        {'error': 'Screenshot returned an invalid result'},
        isError: true,
      );
    }

    if (result.containsKey('error')) {
      return _textToolCallResult(result, isError: true);
    }

    final imageData = result['image'];
    final format = result['format'];
    if (imageData is! String ||
        imageData.isEmpty ||
        (format != 'png' && format != 'jpeg')) {
      return _textToolCallResult(
        {'error': 'Screenshot returned invalid image data or format'},
        isError: true,
      );
    }

    final metadata = Map<String, dynamic>.from(result)..remove('image');
    final mimeType = format == 'jpeg' ? 'image/jpeg' : 'image/png';
    return {
      'content': [
        {'type': 'image', 'data': imageData, 'mimeType': mimeType},
        {'type': 'text', 'text': jsonEncode(metadata)},
      ],
      'structuredContent': metadata,
    };
  }
}
