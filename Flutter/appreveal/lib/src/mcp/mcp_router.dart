// MCP tool registry and JSON-RPC 2.0 dispatch.

import 'dart:convert';

typedef MCPToolHandler = Future<dynamic> Function(Map<String, dynamic>? params);

class MCPToolDefinition {
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;
  final MCPToolHandler handler;

  const MCPToolDefinition({
    required this.name,
    required this.description,
    required this.inputSchema,
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
          'serverInfo': {'name': 'AppReveal', 'version': '0.7.0'},
        });

      case 'tools/list':
        final toolList = _tools.values.map((t) => {
          'name': t.name,
          'description': t.description,
          'inputSchema': t.inputSchema,
        }).toList();
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
          final resultJson = jsonEncode(result);
          return _response(id, {
            'content': [{'type': 'text', 'text': resultJson}],
          });
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
}
