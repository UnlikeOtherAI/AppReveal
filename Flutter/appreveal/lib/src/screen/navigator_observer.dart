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
  final _routes = <Route<dynamic>>[];

  String get currentRoute => _routes.isEmpty ? '/' : _routeName(_routes.last);
  Route<dynamic>? get currentRouteObject => _routes.lastOrNull;
  List<String> get routeStack => List.unmodifiable(_routes.map(_routeName));
  List<String> get presentedModals => List.unmodifiable(
      _routes.whereType<PopupRoute<dynamic>>().map(_routeName));

  NavigatorState? get navigatorState => navigator;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index < 0) return;
    if (newRoute == null) {
      _routes.removeAt(index);
    } else {
      _routes[index] = newRoute;
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
  }

  static String _routeName(Route<dynamic> route) =>
      route.settings.name ?? route.runtimeType.toString();
}
