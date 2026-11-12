// WebView registry and JavaScript execution bridge.

import 'dart:convert';
import 'dart:io';

import 'package:webview_flutter/webview_flutter.dart';

class WebViewEntry {
  final String id;
  final WebViewController controller;
  String? title;
  bool loading;
  String? frame;

  WebViewEntry({
    required this.id,
    required this.controller,
    this.title,
    this.loading = false,
    this.frame,
  });
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
  void register(
    String id,
    WebViewController controller, {
    String? title,
    bool loading = false,
    String? frame,
  }) {
    _webViews[id] = WebViewEntry(
      id: id,
      controller: controller,
      title: title,
      loading: loading,
      frame: frame,
    );
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
        'loading': entry.loading,
        'canGoBack': await entry.controller.canGoBack(),
        'canGoForward': await entry.controller.canGoForward(),
        'frame': entry.frame ?? '',
      });
    }
    return results;
  }

  Future<String> evaluate({required String js, String? webViewId}) async {
    final controller = resolve(id: webViewId);
    if (controller == null) {
      throw Exception(
          'WebView not found${webViewId != null ? ': $webViewId' : ''}');
    }
    final result = await controller.runJavaScriptReturningResult(js);
    return decodeResult(result, jsonEncodedString: Platform.isAndroid);
  }

  /// Android can return a JSON-quoted JS string; iOS returns the string itself.
  /// Decode once so escaped backslashes, tabs and Unicode survive unchanged.
  static String decodeResult(Object result, {bool jsonEncodedString = false}) {
    final raw = result.toString();
    if (!jsonEncodedString) return raw;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is String) return decoded;
    } on FormatException {
      // Arbitrary web_evaluate output need not be JSON.
    }
    return raw;
  }
}
