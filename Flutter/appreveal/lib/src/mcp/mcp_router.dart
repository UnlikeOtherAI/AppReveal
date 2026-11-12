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
    final method = request['method'];
    if (request['jsonrpc'] != '2.0' ||
        method is! String ||
        (id != null && id is! String && id is! num)) {
      return _error(null, -32600, 'Invalid JSON-RPC request');
    }
    if (request['params'] != null &&
        request['params'] is! Map<String, dynamic>) {
      return _error(id, -32602, 'params must be an object');
    }

    switch (method) {
      case 'initialize':
        return _response(id, {
          'protocolVersion': '2025-06-18',
          'capabilities': {'tools': {}},
          'serverInfo': {'name': 'AppReveal', 'version': '0.10.1'},
        });

      case 'ping':
        return _response(id, <String, dynamic>{});

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
        final toolName = params?['name'];
        if (toolName is! String) {
          return _error(id, -32602, 'Missing tool name');
        }
        final definition = _tools[toolName];
        if (definition == null) {
          return _error(id, -32601, 'Tool not found: $toolName');
        }
        try {
          final arguments = params?['arguments'];
          if (arguments != null && arguments is! Map<String, dynamic>) {
            return _error(id, -32602, 'arguments must be an object');
          }
          final args = arguments as Map<String, dynamic>?;
          final validation =
              validateArguments(definition.inputSchema, args ?? {});
          if (validation != null) return _error(id, -32602, validation);
          final result = await definition.handler(args);
          return _response(id, _toolCallResult(result, definition.outputKind));
        } catch (e) {
          return _response(
              id, _textToolCallResult({'error': e.toString()}, isError: true));
        }

      default:
        return _error(id, -32601, 'Method not found: $method');
    }
  }

  /// Some successful diagnostic results include an empty error field.
  static bool isToolFailure(dynamic result) {
    if (result is! Map) return false;
    final error = result['error'];
    return result['success'] == false ||
        (error is String && error.trim().isNotEmpty);
  }

  static String? validateArguments(Map<String, dynamic> schema, dynamic value,
      [String path = 'arguments']) {
    final type = schema['type'];
    final valid = switch (type) {
      'object' => value is Map<String, dynamic>,
      'array' => value is List,
      'string' => value is String,
      'boolean' => value is bool,
      'integer' => value is int,
      'number' => value is num && value.isFinite,
      _ => true,
    };
    if (!valid) return '$path must be $type';
    if (schema['enum'] is List && !(schema['enum'] as List).contains(value)) {
      return '$path has an unsupported value';
    }
    if (value is num &&
        schema['minimum'] is num &&
        value < (schema['minimum'] as num)) {
      return '$path is below its minimum';
    }
    if (value is Map<String, dynamic>) {
      for (final key in (schema['required'] as List? ?? [])) {
        if (!value.containsKey(key)) return '$path.$key is required';
      }
      final properties = schema['properties'] as Map? ?? {};
      for (final entry in value.entries) {
        final child = properties[entry.key];
        if (child is Map<String, dynamic>) {
          final error =
              validateArguments(child, entry.value, '$path.${entry.key}');
          if (error != null) return error;
        }
      }
    }
    if (value is List && schema['items'] is Map<String, dynamic>) {
      for (var index = 0; index < value.length; index++) {
        final error = validateArguments(schema['items'] as Map<String, dynamic>,
            value[index], '$path[$index]');
        if (error != null) return error;
      }
    }
    return null;
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
    if (isError || isToolFailure(result)) response['isError'] = true;
    return response;
  }

  static Map<String, dynamic> _imageToolCallResult(dynamic result) {
    if (result is! Map<String, dynamic>) {
      return _textToolCallResult(
        {'error': 'Screenshot returned an invalid result'},
        isError: true,
      );
    }

    if (isToolFailure(result)) {
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
