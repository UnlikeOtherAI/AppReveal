// WebView registry and JavaScript execution bridge.

import 'package:webview_flutter/webview_flutter.dart';

class WebViewEntry {
  final String id;
  final WebViewController controller;
  String? title;

  WebViewEntry({required this.id, required this.controller, this.title});
}

class WebViewBridge {
  static final shared = WebViewBridge._();
  WebViewBridge._();

  final _webViews = <String, WebViewEntry>{};

  /// Register a WebViewController with an explicit ID.
  /// Call this after creating a WebViewController:
  /// ```dart
  /// AppReveal.registerWebView('main', myWebViewController);
  /// ```
  void register(String id, WebViewController controller, {String? title}) {
    _webViews[id] = WebViewEntry(id: id, controller: controller, title: title);
  }

  void unregister(String id) {
    _webViews.remove(id);
  }

  WebViewController? resolve({String? id}) {
    if (id != null) return _webViews[id]?.controller;
    return _webViews.values.firstOrNull?.controller;
  }

  Future<List<Map<String, dynamic>>> webViewInfo() async {
    final results = <Map<String, dynamic>>[];
    for (final entry in _webViews.values) {
      final url = await entry.controller.currentUrl();
      final title = entry.title ?? '';
      results.add({
        'id': entry.id,
        'url': url ?? '',
        'title': title,
        'canGoBack': await entry.controller.canGoBack(),
        'canGoForward': await entry.controller.canGoForward(),
      });
    }
    return results;
  }

  Future<String> evaluate({required String js, String? webViewId}) async {
    final controller = resolve(id: webViewId);
    if (controller == null) throw Exception('WebView not found${webViewId != null ? ': $webViewId' : ''}');
    final result = await controller.runJavaScriptReturningResult(js);
    // webview_flutter returns the JSON-encoded string result — unwrap it
    final raw = result.toString();
    if (raw.startsWith('"') && raw.endsWith('"')) {
      return raw
          .substring(1, raw.length - 1)
          .replaceAll('\\"', '"')
          .replaceAll('\\\\', '\\')
          .replaceAll('\\n', '\n')
          .replaceAll('\\r', '\r');
    }
    return raw;
  }
}
