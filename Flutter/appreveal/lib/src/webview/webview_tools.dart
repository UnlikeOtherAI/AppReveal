// Registers all 21 WebView MCP tools.

import 'dom_serializer.dart';
import 'webview_bridge.dart';
import '../mcp/mcp_router.dart';

void registerWebViewTools() {
  final router = MCPRouter.shared;
  final bridge = WebViewBridge.shared;

  // MARK: - get_webviews

  router.register(MCPToolDefinition(
    name: 'get_webviews',
    description: 'List all registered WebView instances with URL, title, and navigation state',
    inputSchema: {'type': 'object', 'properties': <String, dynamic>{}},
    handler: (_) async {
      final info = await bridge.webViewInfo();
      return {'webviews': info, 'count': info.length};
    },
  ));

  // MARK: - get_dom_tree

  router.register(MCPToolDefinition(
    name: 'get_dom_tree',
    description: 'Get the DOM tree of a web view. Returns full or partial DOM structure as JSON.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'webview_id': {'type': 'string', 'description': 'Web view ID (default: first registered)'},
        'root': {'type': 'string', 'description': 'CSS selector for subtree root (default: body)'},
        'max_depth': {'type': 'integer', 'description': 'Max tree depth (default: 30)'},
        'visible_only': {'type': 'boolean', 'description': 'Only visible elements (default: false)'},
      },
    },
    handler: (params) async {
      final js = DOMSerializer.dumpTreeJS(
        root: params?['root'] as String?,
        maxDepth: params?['max_depth'] as int? ?? 30,
        visibleOnly: params?['visible_only'] as bool? ?? false,
      );
      try {
        final result = await bridge.evaluate(js: js, webViewId: params?['webview_id'] as String?);
        return {'dom': result};
      } catch (e) {
        return {'error': e.toString()};
      }
    },
  ));

  // MARK: - get_dom_interactive

  router.register(MCPToolDefinition(
    name: 'get_dom_interactive',
    description: 'Get all interactive DOM elements (inputs, buttons, links, selects) with their attributes, values, and selectors',
    inputSchema: {
      'type': 'object',
      'properties': {
        'webview_id': {'type': 'string', 'description': 'Web view ID (default: first registered)'},
      },
    },
    handler: (params) async {
      try {
        final result = await bridge.evaluate(
          js: DOMSerializer.interactiveJS(),
          webViewId: params?['webview_id'] as String?,
        );
        return {'result': result};
      } catch (e) {
        return {'error': e.toString()};
      }
    },
  ));

  // MARK: - query_dom

  router.register(MCPToolDefinition(
    name: 'query_dom',
    description: 'Query the DOM with a CSS selector. Returns matching elements with tag, text, attributes, rect.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'selector': {'type': 'string', 'description': 'CSS selector'},
        'webview_id': {'type': 'string', 'description': 'Web view ID (default: first registered)'},
        'limit': {'type': 'integer', 'description': 'Max results (default: 50)'},
      },
      'required': ['selector'],
    },
    handler: (params) async {
      final selector = params?['selector'] as String?;
      if (selector == null) return {'error': 'selector required'};
      final js = DOMSerializer.queryJS(selector, limit: params?['limit'] as int? ?? 50);
      try {
        final result = await bridge.evaluate(js: js, webViewId: params?['webview_id'] as String?);
        return {'result': result};
      } catch (e) {
        return {'error': e.toString()};
      }
    },
  ));

  // MARK: - find_dom_text

  router.register(MCPToolDefinition(
    name: 'find_dom_text',
    description: 'Find DOM elements containing specific text',
    inputSchema: {
      'type': 'object',
      'properties': {
        'text': {'type': 'string', 'description': 'Text to search for'},
        'tag': {'type': 'string', 'description': "Optional tag filter (e.g. 'button', 'a')"},
        'webview_id': {'type': 'string', 'description': 'Web view ID (default: first registered)'},
      },
      'required': ['text'],
    },
    handler: (params) async {
      final text = params?['text'] as String?;
      if (text == null) return {'error': 'text required'};
      final js = DOMSerializer.findTextJS(text, tag: params?['tag'] as String?);
      try {
        final result = await bridge.evaluate(js: js, webViewId: params?['webview_id'] as String?);
        return {'result': result};
      } catch (e) {
        return {'error': e.toString()};
      }
    },
  ));

  // MARK: - web_click

  router.register(MCPToolDefinition(
    name: 'web_click',
    description: 'Click a DOM element by CSS selector',
    inputSchema: {
      'type': 'object',
      'properties': {
        'selector': {'type': 'string', 'description': 'CSS selector'},
        'webview_id': {'type': 'string', 'description': 'Web view ID (default: first registered)'},
      },
      'required': ['selector'],
    },
    handler: (params) async {
      final selector = params?['selector'] as String?;
      if (selector == null) return {'error': 'selector required'};
      try {
        final result = await bridge.evaluate(
          js: DOMSerializer.clickJS(selector),
          webViewId: params?['webview_id'] as String?,
        );
        return {'result': result};
      } catch (e) {
        return {'error': e.toString()};
      }
    },
  ));

  // MARK: - web_type

  router.register(MCPToolDefinition(
    name: 'web_type',
    description: 'Type text into a DOM input or textarea by CSS selector',
    inputSchema: {
      'type': 'object',
      'properties': {
        'selector': {'type': 'string', 'description': 'CSS selector'},
        'text': {'type': 'string', 'description': 'Text to type'},
        'clear': {'type': 'boolean', 'description': 'Clear field first (default: false)'},
        'webview_id': {'type': 'string', 'description': 'Web view ID (default: first registered)'},
      },
      'required': ['selector', 'text'],
    },
    handler: (params) async {
      final selector = params?['selector'] as String?;
      final text = params?['text'] as String?;
      if (selector == null || text == null) return {'error': 'selector and text required'};
      try {
        final result = await bridge.evaluate(
          js: DOMSerializer.typeJS(selector, text, clear: params?['clear'] as bool? ?? false),
          webViewId: params?['webview_id'] as String?,
        );
        return {'result': result};
      } catch (e) {
        return {'error': e.toString()};
      }
    },
  ));

  // MARK: - web_select

  router.register(MCPToolDefinition(
    name: 'web_select',
    description: 'Select an option in a dropdown by CSS selector',
    inputSchema: {
      'type': 'object',
      'properties': {
        'selector': {'type': 'string', 'description': 'CSS selector for the select element'},
        'value': {'type': 'string', 'description': 'Option value to select'},
        'webview_id': {'type': 'string', 'description': 'Web view ID (default: first registered)'},
      },
      'required': ['selector', 'value'],
    },
    handler: (params) async {
      final selector = params?['selector'] as String?;
      final value = params?['value'] as String?;
      if (selector == null || value == null) return {'error': 'selector and value required'};
      try {
        final result = await bridge.evaluate(
          js: DOMSerializer.selectJS(selector, value),
          webViewId: params?['webview_id'] as String?,
        );
        return {'result': result};
      } catch (e) {
        return {'error': e.toString()};
      }
    },
  ));

  // MARK: - web_toggle

  router.register(MCPToolDefinition(
    name: 'web_toggle',
    description: 'Check or uncheck a checkbox/radio by CSS selector',
    inputSchema: {
      'type': 'object',
      'properties': {
        'selector': {'type': 'string', 'description': 'CSS selector'},
        'checked': {'type': 'boolean', 'description': 'Desired checked state'},
        'webview_id': {'type': 'string', 'description': 'Web view ID (default: first registered)'},
      },
      'required': ['selector', 'checked'],
    },
    handler: (params) async {
      final selector = params?['selector'] as String?;
      final checked = params?['checked'] as bool?;
      if (selector == null || checked == null) return {'error': 'selector and checked required'};
      try {
        final result = await bridge.evaluate(
          js: DOMSerializer.toggleJS(selector, checked),
          webViewId: params?['webview_id'] as String?,
        );
        return {'result': result};
      } catch (e) {
        return {'error': e.toString()};
      }
    },
  ));

  // MARK: - web_scroll_to

  router.register(MCPToolDefinition(
    name: 'web_scroll_to',
    description: 'Scroll a web view until a DOM element is visible',
    inputSchema: {
      'type': 'object',
      'properties': {
        'selector': {'type': 'string', 'description': 'CSS selector'},
        'webview_id': {'type': 'string', 'description': 'Web view ID (default: first registered)'},
      },
      'required': ['selector'],
    },
    handler: (params) async {
      final selector = params?['selector'] as String?;
      if (selector == null) return {'error': 'selector required'};
      try {
        final result = await bridge.evaluate(
          js: DOMSerializer.scrollToJS(selector),
          webViewId: params?['webview_id'] as String?,
        );
        return {'result': result};
      } catch (e) {
        return {'error': e.toString()};
      }
    },
  ));

  // MARK: - web_evaluate

  router.register(MCPToolDefinition(
    name: 'web_evaluate',
    description: 'Run arbitrary JavaScript in a web view and return the result',
    inputSchema: {
      'type': 'object',
      'properties': {
        'javascript': {'type': 'string', 'description': 'JavaScript to evaluate'},
        'webview_id': {'type': 'string', 'description': 'Web view ID (default: first registered)'},
      },
      'required': ['javascript'],
    },
    handler: (params) async {
      final js = params?['javascript'] as String?;
      if (js == null) return {'error': 'javascript required'};
      try {
        final result = await bridge.evaluate(js: js, webViewId: params?['webview_id'] as String?);
        return {'result': result};
      } catch (e) {
        return {'error': e.toString()};
      }
    },
  ));

  // MARK: - web_navigate

  router.register(MCPToolDefinition(
    name: 'web_navigate',
    description: 'Navigate a web view to a URL',
    inputSchema: {
      'type': 'object',
      'properties': {
        'url': {'type': 'string', 'description': 'URL to navigate to'},
        'webview_id': {'type': 'string', 'description': 'Web view ID (default: first registered)'},
      },
      'required': ['url'],
    },
    handler: (params) async {
      final url = params?['url'] as String?;
      if (url == null) return {'error': 'url required'};
      final controller = bridge.resolve(id: params?['webview_id'] as String?);
      if (controller == null) return {'error': 'WebView not found'};
      try {
        await controller.loadRequest(Uri.parse(url));
        return {'success': true, 'url': url};
      } catch (e) {
        return {'error': e.toString()};
      }
    },
  ));

  // MARK: - web_back

  router.register(MCPToolDefinition(
    name: 'web_back',
    description: 'Go back in web view history',
    inputSchema: {
      'type': 'object',
      'properties': {
        'webview_id': {'type': 'string', 'description': 'Web view ID (default: first registered)'},
      },
    },
    handler: (params) async {
      final controller = bridge.resolve(id: params?['webview_id'] as String?);
      if (controller == null) return {'error': 'WebView not found'};
      if (!await controller.canGoBack()) return {'error': 'Cannot go back'};
      await controller.goBack();
      return {'success': true};
    },
  ));

  // MARK: - web_forward

  router.register(MCPToolDefinition(
    name: 'web_forward',
    description: 'Go forward in web view history',
    inputSchema: {
      'type': 'object',
      'properties': {
        'webview_id': {'type': 'string', 'description': 'Web view ID (default: first registered)'},
      },
    },
    handler: (params) async {
      final controller = bridge.resolve(id: params?['webview_id'] as String?);
      if (controller == null) return {'error': 'WebView not found'};
      if (!await controller.canGoForward()) return {'error': 'Cannot go forward'};
      await controller.goForward();
      return {'success': true};
    },
  ));

  // MARK: - get_dom_links

  router.register(MCPToolDefinition(
    name: 'get_dom_links',
    description: 'Get all links on the page — just text and href. Minimal tokens.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'webview_id': {'type': 'string', 'description': 'Web view ID (default: first registered)'},
      },
    },
    handler: (params) async {
      try {
        final result = await bridge.evaluate(
          js: DOMSerializer.linksJS(),
          webViewId: params?['webview_id'] as String?,
        );
        return {'result': result};
      } catch (e) {
        return {'error': e.toString()};
      }
    },
  ));

  // MARK: - get_dom_text

  router.register(MCPToolDefinition(
    name: 'get_dom_text',
    description: 'Get visible text content of the page stripped of all markup. Optionally scope to a CSS selector. Minimal tokens.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'selector': {'type': 'string', 'description': 'CSS selector to scope text extraction (default: body)'},
        'webview_id': {'type': 'string', 'description': 'Web view ID (default: first registered)'},
      },
    },
    handler: (params) async {
      final js = DOMSerializer.textContentJS(selector: params?['selector'] as String?);
      try {
        final result = await bridge.evaluate(js: js, webViewId: params?['webview_id'] as String?);
        return {'result': result};
      } catch (e) {
        return {'error': e.toString()};
      }
    },
  ));

  // MARK: - get_dom_forms

  router.register(MCPToolDefinition(
    name: 'get_dom_forms',
    description: 'Get all forms and their fields with types, names, values, options, and selectors. Includes pages without <form> tags.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'webview_id': {'type': 'string', 'description': 'Web view ID (default: first registered)'},
      },
    },
    handler: (params) async {
      try {
        final result = await bridge.evaluate(
          js: DOMSerializer.formsJS(),
          webViewId: params?['webview_id'] as String?,
        );
        return {'result': result};
      } catch (e) {
        return {'error': e.toString()};
      }
    },
  ));

  // MARK: - get_dom_headings

  router.register(MCPToolDefinition(
    name: 'get_dom_headings',
    description: 'Get all headings (h1-h6) for page structure overview. Minimal tokens.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'webview_id': {'type': 'string', 'description': 'Web view ID (default: first registered)'},
      },
    },
    handler: (params) async {
      try {
        final result = await bridge.evaluate(
          js: DOMSerializer.headingsJS(),
          webViewId: params?['webview_id'] as String?,
        );
        return {'result': result};
      } catch (e) {
        return {'error': e.toString()};
      }
    },
  ));

  // MARK: - get_dom_images

  router.register(MCPToolDefinition(
    name: 'get_dom_images',
    description: 'Get all visible images with src, alt text, and dimensions.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'webview_id': {'type': 'string', 'description': 'Web view ID (default: first registered)'},
      },
    },
    handler: (params) async {
      try {
        final result = await bridge.evaluate(
          js: DOMSerializer.imagesJS(),
          webViewId: params?['webview_id'] as String?,
        );
        return {'result': result};
      } catch (e) {
        return {'error': e.toString()};
      }
    },
  ));

  // MARK: - get_dom_tables

  router.register(MCPToolDefinition(
    name: 'get_dom_tables',
    description: 'Get all tables with headers and row data.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'webview_id': {'type': 'string', 'description': 'Web view ID (default: first registered)'},
      },
    },
    handler: (params) async {
      try {
        final result = await bridge.evaluate(
          js: DOMSerializer.tablesJS(),
          webViewId: params?['webview_id'] as String?,
        );
        return {'result': result};
      } catch (e) {
        return {'error': e.toString()};
      }
    },
  ));

  // MARK: - get_dom_summary

  router.register(MCPToolDefinition(
    name: 'get_dom_summary',
    description: 'Get a compact page summary: title, meta, headings (h1-h3), element counts (links, images, inputs, buttons), and form overview. Cheapest way to understand a page.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'webview_id': {'type': 'string', 'description': 'Web view ID (default: first registered)'},
      },
    },
    handler: (params) async {
      try {
        final result = await bridge.evaluate(
          js: DOMSerializer.summaryJS(),
          webViewId: params?['webview_id'] as String?,
        );
        return {'result': result};
      } catch (e) {
        return {'error': e.toString()};
      }
    },
  ));
}
