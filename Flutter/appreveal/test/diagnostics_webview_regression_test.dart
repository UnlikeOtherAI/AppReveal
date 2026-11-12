import 'dart:convert';
import 'package:appreveal/src/diagnostics/diagnostics_bridge.dart';
import 'package:appreveal/src/webview/webview_bridge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('diagnostics install is idempotent and restores the app handlers', () {
    final savedPrint = debugPrint;
    final savedError = FlutterError.onError;
    var prints = 0;
    var errors = 0;
    debugPrint = (String? message, {int? wrapWidth}) {
      prints++;
    };
    FlutterError.onError = (_) {
      errors++;
    };
    final bridge = DiagnosticsBridge.shared;
    try {
      bridge.install();
      bridge.install();
      debugPrint('diagnostics probe');
      FlutterError.reportError(
          FlutterErrorDetails(exception: StateError('probe')));
      expect(prints, 1);
      expect(errors, 1);
      expect(
          bridge
              .getRecentLogs()
              .where((entry) => entry['message'] == 'diagnostics probe'),
          hasLength(1));
      bridge.uninstall();
      debugPrint('after stop');
      expect(prints, 2);
      expect(
          bridge
              .getRecentLogs()
              .where((entry) => entry['message'] == 'after stop'),
          isEmpty);
    } finally {
      bridge.uninstall();
      debugPrint = savedPrint;
      FlutterError.onError = savedError;
    }
  });
  test('WebView results preserve escaped strings on Android and iOS', () {
    const values = [
      'line\nnext\tcolumn',
      r'literal\n\t\u0041',
      'quotes " and slash \\',
      'žluťoučký 🐈'
    ];
    for (final value in values) {
      final document = jsonEncode({'text': value});
      expect(WebViewBridge.decodeResult(document), document);
      expect(
          WebViewBridge.decodeResult(jsonEncode(document),
              jsonEncodedString: true),
          document);
    }
    expect(WebViewBridge.decodeResult('"quoted literal"'), '"quoted literal"');
    expect(WebViewBridge.decodeResult('plain text'), 'plain text');
    expect(WebViewBridge.decodeResult(true), 'true');
  });
}
