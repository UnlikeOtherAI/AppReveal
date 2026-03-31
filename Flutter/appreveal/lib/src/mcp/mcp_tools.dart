// Registers all 22 built-in native Flutter MCP tools.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../diagnostics/diagnostics_bridge.dart';
import '../elements/element_inventory.dart';
import '../elements/element_resolver.dart';
import '../interaction/interaction_engine.dart';
import '../network/network_observer.dart';
import '../screenshot/screenshot_capture.dart';
import '../screen/screen_resolver.dart';
import '../state/state_bridge.dart';
import 'mcp_router.dart';

void registerBuiltInTools() {
  final router = MCPRouter.shared;

  // MARK: - get_screen

  router.register(MCPToolDefinition(
    name: 'get_screen',
    description: 'Get the currently active screen identity and metadata',
    inputSchema: {'type': 'object', 'properties': <String, dynamic>{}},
    handler: (_) async {
      return ScreenResolver.shared.resolve().toMap();
    },
  ));

  // MARK: - get_elements

  router.register(MCPToolDefinition(
    name: 'get_elements',
    description: 'List all visible interactive elements on the current screen',
    inputSchema: {'type': 'object', 'properties': <String, dynamic>{}},
    handler: (_) async {
      final elements = ElementInventory.shared.listElements();
      return {
        'screenKey': ScreenResolver.shared.resolve().screenKey,
        'elements': elements,
      };
    },
  ));

  // MARK: - get_view_tree

  router.register(MCPToolDefinition(
    name: 'get_view_tree',
    description: 'Dump the full widget hierarchy of the current screen. Returns every widget with type, frame, properties, and depth. Use for discovering all objects on screen.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'max_depth': {'type': 'integer', 'description': 'Max hierarchy depth (default 50)'},
      },
    },
    handler: (params) async {
      final maxDepth = params?['max_depth'] as int? ?? 50;
      final tree = ElementInventory.shared.dumpWidgetTree(maxDepth: maxDepth);
      return {'views': tree, 'count': tree.length};
    },
  ));

  // MARK: - screenshot

  router.register(MCPToolDefinition(
    name: 'screenshot',
    description: 'Capture a screenshot of the current screen. Returns base64-encoded image.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'element_id': {'type': 'string', 'description': 'Optional element ID to crop to'},
        'format': {'type': 'string', 'enum': ['png', 'jpeg'], 'description': 'Image format (default: png)'},
      },
    },
    handler: (params) async {
      final format = params?['format'] as String? ?? 'png';
      final elementId = params?['element_id'] as String?;
      if (elementId != null) {
        return ScreenshotCapture.shared.captureElement(elementId: elementId, format: format);
      }
      return ScreenshotCapture.shared.captureScreen(format: format);
    },
  ));

  // MARK: - tap_element

  router.register(MCPToolDefinition(
    name: 'tap_element',
    description:
        'Tap an element by its ID. Resolves by ValueKey first, then semantics label, then derived text ID. For text-based targeting use tap_text instead.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'element_id': {
          'type': 'string',
          'description': 'Element ID from get_elements'
        },
      },
      'required': ['element_id'],
    },
    handler: (params) async {
      final id = params?['element_id'] as String?;
      if (id == null) return {'error': 'element_id required'};
      try {
        await InteractionEngine.shared.tap(elementId: id);
        return {'success': true, 'element_id': id};
      } catch (e) {
        final msg = e.toString();
        final response = <String, dynamic>{'error': msg};
        if (msg.contains('not found')) {
          response['hint'] =
              'Use tap_text to target by visible text, or get_elements to list available IDs.';
        }
        return response;
      }
    },
  ));

  // MARK: - tap_text

  router.register(MCPToolDefinition(
    name: 'tap_text',
    description:
        'Tap a visible text element on screen. Finds the text and taps its nearest tappable ancestor widget. '
        'Works for buttons, list tiles, and any tappable container with visible text — no ValueKey required.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'text': {
          'type': 'string',
          'description': 'Visible text to find and tap'
        },
        'match_mode': {
          'type': 'string',
          'enum': ['exact', 'contains'],
          'description': 'Match mode: exact (default) or contains',
        },
        'occurrence': {
          'type': 'integer',
          'description':
              '0-based index when multiple elements match the same text. Omit for single-match auto-tap.',
        },
      },
      'required': ['text'],
    },
    handler: (params) async {
      final text = params?['text'] as String?;
      if (text == null) return {'error': 'text required'};
      final matchMode = params?['match_mode'] as String? ?? 'exact';
      final occurrence = params?['occurrence'] as int?;

      try {
        final result = ElementResolver.shared.resolveByText(
          text,
          matchMode: matchMode,
          occurrence: occurrence,
        );

        if (!result.isSuccess) {
          final response = <String, dynamic>{'error': result.error};
          if (result.candidates != null) {
            response['candidates'] = result.candidates;
            response['match_count'] = result.candidates!.length;
          }
          return response;
        }

        await InteractionEngine.shared.tapElement(result.element!);
        return {'success': true, 'text': text};
      } catch (e) {
        return {'error': e.toString()};
      }
    },
  ));

  // MARK: - tap_point

  router.register(MCPToolDefinition(
    name: 'tap_point',
    description: 'Tap at specific screen coordinates',
    inputSchema: {
      'type': 'object',
      'properties': {
        'x': {'type': 'number'},
        'y': {'type': 'number'},
      },
      'required': ['x', 'y'],
    },
    handler: (params) async {
      final x = (params?['x'] as num?)?.toDouble() ?? 0;
      final y = (params?['y'] as num?)?.toDouble() ?? 0;
      await InteractionEngine.shared.tapPoint(x: x, y: y);
      return {'success': true, 'x': x, 'y': y};
    },
  ));

  // MARK: - type_text

  router.register(MCPToolDefinition(
    name: 'type_text',
    description: 'Type text into a text field',
    inputSchema: {
      'type': 'object',
      'properties': {
        'text': {'type': 'string', 'description': 'Text to type'},
        'element_id': {'type': 'string', 'description': 'Optional target element ID'},
      },
      'required': ['text'],
    },
    handler: (params) async {
      final text = params?['text'] as String?;
      if (text == null) return {'error': 'text required'};
      try {
        await InteractionEngine.shared.typeText(
          text: text,
          elementId: params?['element_id'] as String?,
        );
        return {'success': true, 'text': text};
      } catch (e) {
        return {'error': e.toString()};
      }
    },
  ));

  // MARK: - clear_text

  router.register(MCPToolDefinition(
    name: 'clear_text',
    description: 'Clear a text field',
    inputSchema: {
      'type': 'object',
      'properties': {
        'element_id': {'type': 'string'},
      },
      'required': ['element_id'],
    },
    handler: (params) async {
      final id = params?['element_id'] as String?;
      if (id == null) return {'error': 'element_id required'};
      try {
        await InteractionEngine.shared.clearText(elementId: id);
        return {'success': true};
      } catch (e) {
        return {'error': e.toString()};
      }
    },
  ));

  // MARK: - scroll

  router.register(MCPToolDefinition(
    name: 'scroll',
    description: 'Scroll a container in a direction. container_id accepts explicit keys or derived IDs from get_elements.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'direction': {'type': 'string', 'enum': ['up', 'down', 'left', 'right']},
        'container_id': {'type': 'string', 'description': 'Optional scroll container ID'},
      },
      'required': ['direction'],
    },
    handler: (params) async {
      final direction = params?['direction'] as String?;
      if (direction == null) return {'error': 'direction required'};
      try {
        await InteractionEngine.shared.scroll(
          direction: direction,
          containerId: params?['container_id'] as String?,
        );
        return {'success': true};
      } catch (e) {
        return {'error': e.toString()};
      }
    },
  ));

  // MARK: - scroll_to_element

  router.register(MCPToolDefinition(
    name: 'scroll_to_element',
    description: 'Scroll until an element is visible. Accepts explicit or derived element IDs from get_elements.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'element_id': {'type': 'string'},
      },
      'required': ['element_id'],
    },
    handler: (params) async {
      final id = params?['element_id'] as String?;
      if (id == null) return {'error': 'element_id required'};
      try {
        await InteractionEngine.shared.scrollToElement(elementId: id);
        return {'success': true};
      } catch (e) {
        return {'error': e.toString()};
      }
    },
  ));

  // MARK: - select_tab

  router.register(MCPToolDefinition(
    name: 'select_tab',
    description: 'Switch to a tab by index (0-based)',
    inputSchema: {
      'type': 'object',
      'properties': {
        'index': {'type': 'integer', 'description': 'Tab index (0-based)'},
      },
      'required': ['index'],
    },
    handler: (params) async {
      final index = params?['index'] as int?;
      if (index == null) return {'error': 'index required'};
      try {
        await InteractionEngine.shared.selectTab(index: index);
        return {'success': true, 'tab_index': index};
      } catch (e) {
        return {'error': e.toString()};
      }
    },
  ));

  // MARK: - navigate_back

  router.register(MCPToolDefinition(
    name: 'navigate_back',
    description: 'Pop the current navigation route',
    inputSchema: {'type': 'object', 'properties': <String, dynamic>{}},
    handler: (_) async {
      try {
        await InteractionEngine.shared.navigateBack();
        return {'success': true};
      } catch (e) {
        return {'error': e.toString()};
      }
    },
  ));

  // MARK: - dismiss_modal

  router.register(MCPToolDefinition(
    name: 'dismiss_modal',
    description: 'Dismiss the topmost modal or dialog',
    inputSchema: {'type': 'object', 'properties': <String, dynamic>{}},
    handler: (_) async {
      try {
        await InteractionEngine.shared.dismissModal();
        return {'success': true};
      } catch (e) {
        return {'error': e.toString()};
      }
    },
  ));

  // MARK: - open_deeplink

  router.register(MCPToolDefinition(
    name: 'open_deeplink',
    description: 'Open a deep link URL',
    inputSchema: {
      'type': 'object',
      'properties': {
        'url': {'type': 'string', 'description': 'Deep link URL'},
      },
      'required': ['url'],
    },
    handler: (params) async {
      final url = params?['url'] as String?;
      if (url == null) return {'error': 'url required'};
      try {
        await InteractionEngine.shared.openDeeplink(url: url);
        return {'success': true, 'url': url};
      } catch (e) {
        return {'error': e.toString()};
      }
    },
  ));

  // MARK: - get_state

  router.register(MCPToolDefinition(
    name: 'get_state',
    description: 'Get the current app state snapshot',
    inputSchema: {'type': 'object', 'properties': <String, dynamic>{}},
    handler: (_) async => StateBridge.shared.getState(),
  ));

  // MARK: - get_navigation_stack

  router.register(MCPToolDefinition(
    name: 'get_navigation_stack',
    description: 'Get the current navigation state',
    inputSchema: {'type': 'object', 'properties': <String, dynamic>{}},
    handler: (_) async => StateBridge.shared.getNavigationStack(),
  ));

  // MARK: - get_feature_flags

  router.register(MCPToolDefinition(
    name: 'get_feature_flags',
    description: 'Get all active feature flags',
    inputSchema: {'type': 'object', 'properties': <String, dynamic>{}},
    handler: (_) async => StateBridge.shared.getFeatureFlags(),
  ));

  // MARK: - get_network_calls

  router.register(MCPToolDefinition(
    name: 'get_network_calls',
    description: 'Get recent network calls',
    inputSchema: {
      'type': 'object',
      'properties': {
        'limit': {'type': 'integer', 'description': 'Max results (default 50)'},
      },
    },
    handler: (params) async {
      final limit = params?['limit'] as int? ?? 50;
      final calls = NetworkObserverService.shared.recentCalls(limit: limit);
      return {'calls': calls, 'count': calls.length};
    },
  ));

  // MARK: - get_logs

  router.register(MCPToolDefinition(
    name: 'get_logs',
    description: 'Get recent app logs',
    inputSchema: {
      'type': 'object',
      'properties': {
        'category': {'type': 'string', 'description': 'Filter by category'},
        'limit': {'type': 'integer', 'description': 'Max results (default 50)'},
      },
    },
    handler: (params) async {
      final logs = DiagnosticsBridge.shared.getRecentLogs(
        category: params?['category'] as String?,
        limit: params?['limit'] as int? ?? 50,
      );
      return {'logs': logs, 'count': logs.length};
    },
  ));

  // MARK: - get_recent_errors

  router.register(MCPToolDefinition(
    name: 'get_recent_errors',
    description: 'Get recent app errors',
    inputSchema: {'type': 'object', 'properties': <String, dynamic>{}},
    handler: (_) async {
      final errors = DiagnosticsBridge.shared.getRecentErrors();
      return {'errors': errors, 'count': errors.length};
    },
  ));

  // MARK: - launch_context

  router.register(MCPToolDefinition(
    name: 'launch_context',
    description: 'Get app launch environment info',
    inputSchema: {'type': 'object', 'properties': <String, dynamic>{}},
    handler: (_) async {
      try {
        final info = await PackageInfo.fromPlatform();
        return {
          'bundleId': info.packageName,
          'version': info.version,
          'build': info.buildNumber,
          'appName': info.appName,
          'platform': Platform.isIOS
              ? 'iOS'
              : Platform.isAndroid
                  ? 'Android'
                  : Platform.operatingSystem,
          'frameworkType': 'flutter',
          'debugMode': kDebugMode,
        };
      } catch (e) {
        return {'error': e.toString()};
      }
    },
  ));

  // MARK: - device_info

  router.register(MCPToolDefinition(
    name: 'device_info',
    description:
        'Return comprehensive device and app information: package metadata, device hardware, OS version, screen dimensions, locale, timezone, memory, and runtime. Single call to get everything an agent needs to understand the runtime environment.',
    inputSchema: {'type': 'object', 'properties': <String, dynamic>{}},
    handler: (_) async {
      try {
        final info = await PackageInfo.fromPlatform();
        final binding = WidgetsBinding.instance;
        final view = binding.platformDispatcher.views.first;
        final physicalSize = view.physicalSize;
        final dpr = view.devicePixelRatio;
        final locale = binding.platformDispatcher.locale;
        final tz = DateTime.now().timeZoneName;
        final tzOffset = DateTime.now().timeZoneOffset;

        // Memory (Dart runtime)
        final runtimeInfo = <String, dynamic>{
          'currentRss': ProcessInfo.currentRss,
          'maxRss': ProcessInfo.maxRss,
        };

        // Screen
        final screenInfo = <String, dynamic>{
          'physicalWidthPx': physicalSize.width.toInt(),
          'physicalHeightPx': physicalSize.height.toInt(),
          'logicalWidthDp': (physicalSize.width / dpr).toInt(),
          'logicalHeightDp': (physicalSize.height / dpr).toInt(),
          'devicePixelRatio': dpr,
        };

        return <String, dynamic>{
          'platform': Platform.isIOS
              ? 'iOS'
              : Platform.isAndroid
                  ? 'Android'
                  : Platform.operatingSystem,
          'frameworkType': 'flutter',
          'debugMode': kDebugMode,

          // App identity
          'bundleId': info.packageName,
          'appName': info.appName,
          'version': info.version,
          'build': info.buildNumber,

          // Runtime
          'operatingSystem': Platform.operatingSystem,
          'operatingSystemVersion': Platform.operatingSystemVersion,
          'numberOfProcessors': Platform.numberOfProcessors,
          'localHostname': Platform.localHostname,

          // Screen
          'screen': screenInfo,

          // Memory
          'memory': runtimeInfo,

          // Locale & timezone
          'locale': {
            'languageCode': locale.languageCode,
            'countryCode': locale.countryCode ?? '',
            'scriptCode': locale.scriptCode ?? '',
            'identifier': locale.toLanguageTag(),
          },
          'timeZone': {
            'name': tz,
            'offsetSeconds': tzOffset.inSeconds,
            'offsetHours': tzOffset.inHours,
          },

          // Environment (non-secret keys only)
          'environment': Platform.environment.entries
              .where((e) =>
                  !e.key.toLowerCase().contains('secret') &&
                  !e.key.toLowerCase().contains('token') &&
                  !e.key.toLowerCase().contains('password') &&
                  !e.key.toLowerCase().contains('key'))
              .fold(<String, String>{},
                  (map, e) => map..[e.key] = e.value),
        };
      } catch (e) {
        return {'error': e.toString()};
      }
    },
  ));

  // MARK: - batch

  router.register(MCPToolDefinition(
    name: 'batch',
    description: 'Execute multiple tool calls in a single request. Actions run sequentially. Each action can have an optional delay_ms (milliseconds to wait BEFORE executing that action) to account for animations, screen transitions, or loading. Returns results for every action.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'actions': {
          'type': 'array',
          'description': 'Array of actions. Each: {"tool": "tool_name", "arguments": {...}, "delay_ms": 500}',
          'items': {
            'type': 'object',
            'properties': {
              'tool': {'type': 'string', 'description': 'Tool name'},
              'arguments': {'type': 'object', 'description': 'Tool arguments'},
              'delay_ms': {'type': 'integer', 'description': 'Milliseconds to wait before this action'},
            },
            'required': ['tool'],
          },
        },
        'stop_on_error': {
          'type': 'boolean',
          'description': 'Stop executing remaining actions if one fails (default: false)',
        },
      },
      'required': ['actions'],
    },
    handler: (params) async {
      final actionsRaw = params?['actions'] as List<dynamic>?;
      if (actionsRaw == null) return {'error': 'actions array required'};

      final stopOnError = params?['stop_on_error'] as bool? ?? false;
      final results = <Map<String, dynamic>>[];

      for (var i = 0; i < actionsRaw.length; i++) {
        final action = actionsRaw[i] as Map<String, dynamic>?;
        final toolName = action?['tool'] as String?;
        if (action == null || toolName == null) {
          results.add({'index': i, 'error': 'Invalid action format'});
          if (stopOnError) break;
          continue;
        }

        final delayMs = action['delay_ms'] as int? ?? 0;
        if (delayMs > 0) {
          await Future<void>.delayed(Duration(milliseconds: delayMs));
        }

        final definition = router.tool(toolName);
        if (definition == null) {
          results.add({'index': i, 'tool': toolName, 'error': 'Tool not found'});
          if (stopOnError) break;
          continue;
        }

        try {
          final args = action['arguments'] as Map<String, dynamic>?;
          final result = await definition.handler(args);
          results.add({'index': i, 'tool': toolName, 'result': result});
        } catch (e) {
          results.add({'index': i, 'tool': toolName, 'error': e.toString()});
          if (stopOnError) break;
        }
      }

      return {'results': results, 'count': results.length};
    },
  ));
}
