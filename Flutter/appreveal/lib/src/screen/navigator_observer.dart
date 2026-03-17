// Navigator observer that tracks the current route and stack.

import 'package:flutter/widgets.dart';

/// Add to [MaterialApp.navigatorObservers] to enable automatic screen tracking.
///
/// ```dart
/// MaterialApp(
///   navigatorObservers: [AppReveal.navigatorObserver],
/// )
/// ```
class AppRevealNavigatorObserver extends NavigatorObserver {
  final _stack = <String>[];
  String _currentRoute = '/';

  String get currentRoute => _currentRoute;
  List<String> get routeStack => List.unmodifiable(_stack);

  /// Returns the [NavigatorState] if a navigator is attached.
  NavigatorState? get navigatorState => navigator;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = _routeName(route);
    _stack.add(name);
    _currentRoute = name;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_stack.isNotEmpty) _stack.removeLast();
    _currentRoute = _stack.isNotEmpty ? _stack.last : '/';
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null) {
      final name = _routeName(newRoute);
      if (_stack.isNotEmpty) {
        _stack[_stack.length - 1] = name;
      } else {
        _stack.add(name);
      }
      _currentRoute = name;
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = _routeName(route);
    _stack.remove(name);
    _currentRoute = _stack.isNotEmpty ? _stack.last : '/';
  }

  static String _routeName(Route<dynamic> route) {
    return route.settings.name ?? route.runtimeType.toString();
  }
}
