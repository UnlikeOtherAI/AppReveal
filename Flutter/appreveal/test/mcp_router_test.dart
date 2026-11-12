import 'dart:convert';

import 'package:appreveal/src/mcp/mcp_router.dart';
import 'package:appreveal/src/mcp/mcp_tools.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('batch stops on returned errors and validates nested arguments',
      () async {
    registerBuiltInTools();
    var ran = 0;
    MCPRouter.shared.register(MCPToolDefinition(
        name: 'batch_fail_probe',
        description: 'failure',
        inputSchema: {'type': 'object', 'properties': {}},
        handler: (_) async => {'error': 'failed'}));
    MCPRouter.shared.register(MCPToolDefinition(
        name: 'batch_count_probe',
        description: 'counter',
        inputSchema: {'type': 'object', 'properties': {}},
        handler: (_) async {
          ran++;
          return {'success': true};
        }));
    final response = await MCPRouter.shared.handle({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'tools/call',
      'params': {
        'name': 'batch',
        'arguments': {
          'stop_on_error': true,
          'actions': [
            {'tool': 'batch_fail_probe'},
            {'tool': 'batch_count_probe'},
          ]
        }
      }
    });
    expect(response['result']['isError'], true);
    final body =
        jsonDecode(response['result']['content'][0]['text'] as String) as Map;
    expect(body['count'], 1);
    expect(ran, 0);
  });

  test('empty diagnostic error fields succeed and do not stop a batch',
      () async {
    registerBuiltInTools();
    for (final error in ['', '  \t\n  ', 'real failure']) {
      MCPRouter.shared.register(MCPToolDefinition(
          name: 'diagnostic_probe',
          description: 'diagnostic',
          inputSchema: {'type': 'object', 'properties': {}},
          handler: (_) async => {'success': true, 'error': error}));
      final single = await callTool('diagnostic_probe');
      expect(single['isError'] == true, error.trim().isNotEmpty);
      final response = await MCPRouter.shared.handle({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/call',
        'params': {
          'name': 'batch',
          'arguments': {
            'stop_on_error': true,
            'actions': [
              {'tool': 'diagnostic_probe'},
              {'tool': 'diagnostic_probe'},
            ]
          }
        }
      });
      final result = response['result'] as Map;
      expect(result['isError'] == true, error.trim().isNotEmpty);
      final body = jsonDecode(result['content'][0]['text'] as String) as Map;
      expect(body['count'], error.trim().isEmpty ? 2 : 1);
    }
  });

  test('image tool returns MCP image block and metadata', () async {
    const toolName = 'test_image_result';
    const imageData = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAAB';
    MCPRouter.shared.register(
      MCPToolDefinition(
        name: toolName,
        description: 'Test image',
        inputSchema: const {'type': 'object', 'properties': {}},
        outputKind: MCPToolOutputKind.image,
        handler: (_) async => {
          'image': imageData,
          'width': 120,
          'height': 240,
          'scale': 2.0,
          'format': 'png',
        },
      ),
    );

    final result = await callTool(toolName);
    final content = result['content'] as List<dynamic>;
    final image = content[0] as Map<String, dynamic>;
    final metadataBlock = content[1] as Map<String, dynamic>;

    expect(content, hasLength(2));
    expect(image['type'], 'image');
    expect(image['data'], imageData);
    expect(image['mimeType'], 'image/png');
    expect(metadataBlock['type'], 'text');

    final metadataText = metadataBlock['text'] as String;
    expect(metadataText, isNot(contains(imageData)));
    final metadataFromText = jsonDecode(metadataText) as Map<String, dynamic>;
    expect(metadataFromText['width'], 120);
    expect(metadataFromText['format'], 'png');
    expect(metadataFromText, isNot(contains('image')));

    final structuredContent =
        result['structuredContent'] as Map<String, dynamic>;
    expect(structuredContent['height'], 240);
    expect(structuredContent['scale'], 2.0);
    expect(structuredContent, isNot(contains('image')));
    expect(result, isNot(contains('isError')));
  });

  test('image tool maps JPEG MIME type', () async {
    const toolName = 'test_jpeg_result';
    MCPRouter.shared.register(
      MCPToolDefinition(
        name: toolName,
        description: 'Test JPEG',
        inputSchema: const {'type': 'object', 'properties': {}},
        outputKind: MCPToolOutputKind.image,
        handler: (_) async => {
          'image': '/9j/4AAQSkZJRgABAQAAAQABAAD',
          'width': 20,
          'height': 10,
          'scale': 1.0,
          'format': 'jpeg',
        },
      ),
    );

    final result = await callTool(toolName);
    final content = result['content'] as List<dynamic>;
    final image = content.first as Map<String, dynamic>;

    expect(image['mimeType'], 'image/jpeg');
  });

  test('image tool failure returns a text error', () async {
    const toolName = 'test_image_failure';
    MCPRouter.shared.register(
      MCPToolDefinition(
        name: toolName,
        description: 'Test image failure',
        inputSchema: const {'type': 'object', 'properties': {}},
        outputKind: MCPToolOutputKind.image,
        handler: (_) async => {'error': 'Capture failed'},
      ),
    );

    final result = await callTool(toolName);
    final content = result['content'] as List<dynamic>;
    final error = content.single as Map<String, dynamic>;

    expect(error['type'], 'text');
    expect(error['text'], contains('Capture failed'));
    expect(result['isError'], isTrue);
    expect(result, isNot(contains('structuredContent')));
  });

  test('JSON tool keeps the text result shape', () async {
    const toolName = 'test_json_result';
    MCPRouter.shared.register(
      MCPToolDefinition(
        name: toolName,
        description: 'Test JSON',
        inputSchema: const {'type': 'object', 'properties': {}},
        handler: (_) async => {'value': 'ok'},
      ),
    );

    final result = await callTool(toolName);
    final content = result['content'] as List<dynamic>;
    final text = content.single as Map<String, dynamic>;

    expect(text['type'], 'text');
    expect(jsonDecode(text['text'] as String), {'value': 'ok'});
    expect(result, isNot(contains('structuredContent')));
  });
}

Future<Map<String, dynamic>> callTool(String name) async {
  final response = await MCPRouter.shared.handle({
    'jsonrpc': '2.0',
    'id': 1,
    'method': 'tools/call',
    'params': {'name': name, 'arguments': <String, dynamic>{}},
  });
  return response['result'] as Map<String, dynamic>;
}
