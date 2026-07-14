import 'dart:convert';

import 'package:appreveal/src/mcp/mcp_router.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
