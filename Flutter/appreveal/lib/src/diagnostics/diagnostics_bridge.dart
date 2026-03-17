// Log and error capture for get_logs and get_recent_errors tools.

import 'package:flutter/foundation.dart';

class DiagnosticsBridge {
  static final shared = DiagnosticsBridge._();
  DiagnosticsBridge._();

  static const _maxLogs = 500;
  static const _maxErrors = 100;

  final _logs = <Map<String, dynamic>>[];
  final _errors = <Map<String, dynamic>>[];

  DebugPrintCallback? _originalDebugPrint;

  void install() {
    // Intercept debugPrint
    _originalDebugPrint = debugPrint;
    debugPrint = _interceptPrint;

    // Capture Flutter framework errors
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      _addError(
        message: details.exceptionAsString(),
        stackTrace: details.stack?.toString(),
        category: 'flutter',
      );
      originalOnError?.call(details);
    };
  }

  void _interceptPrint(String? message, {int? wrapWidth}) {
    _addLog(message ?? '', category: 'debug');
    _originalDebugPrint?.call(message, wrapWidth: wrapWidth);
  }

  void addLog(String message, {String category = 'app'}) {
    _addLog(message, category: category);
  }

  void addError(String message, {String? stackTrace, String? category}) {
    _addError(message: message, stackTrace: stackTrace, category: category);
  }

  void _addLog(String message, {required String category}) {
    _logs.add({
      'timestamp': DateTime.now().toIso8601String(),
      'category': category,
      'message': message,
    });
    if (_logs.length > _maxLogs) _logs.removeAt(0);
  }

  void _addError({required String message, String? stackTrace, String? category}) {
    _errors.add({
      'timestamp': DateTime.now().toIso8601String(),
      'category': category ?? 'app',
      'message': message,
      'stackTrace': stackTrace ?? '',
    });
    if (_errors.length > _maxErrors) _errors.removeAt(0);
  }

  List<Map<String, dynamic>> getRecentLogs({String? category, int limit = 50}) {
    var logs = category != null
        ? _logs.where((l) => l['category'] == category).toList()
        : List<Map<String, dynamic>>.from(_logs);
    if (logs.length > limit) logs = logs.sublist(logs.length - limit);
    return logs.reversed.toList();
  }

  List<Map<String, dynamic>> getRecentErrors({int limit = 50}) {
    var errors = List<Map<String, dynamic>>.from(_errors);
    if (errors.length > limit) errors = errors.sublist(errors.length - limit);
    return errors.reversed.toList();
  }
}
