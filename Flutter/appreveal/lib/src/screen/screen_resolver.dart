// Resolves the currently active screen key, title, and metadata.

// Retain compatibility with Flutter versions before the UI package split.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'screen_identifiable.dart';
import 'navigator_observer.dart';
import '../elements/element_inventory.dart';

class ScreenInfo {
  final String screenKey;
  final String screenTitle;
  final String frameworkType;
  final List<String> routeStack;
  final int navigationDepth;
  final double confidence;
  final String source; // 'explicit', 'route', 'appbar', 'inferred'
  final String? appBarTitle;

  const ScreenInfo({
    required this.screenKey,
    required this.screenTitle,
    required this.frameworkType,
    required this.routeStack,
    required this.navigationDepth,
    required this.confidence,
    this.source = 'explicit',
    this.appBarTitle,
  });

  Map<String, dynamic> toMap() => {
        'screenKey': screenKey,
        'screenTitle': screenTitle,
        'frameworkType': frameworkType,
        'routeStack': routeStack,
        'navigationDepth': navigationDepth,
        'confidence': confidence,
        'source': source,
        if (appBarTitle != null) 'appBarTitle': appBarTitle,
      };
}

class ScreenResolver {
  static final shared = ScreenResolver._();
  ScreenResolver._();

  AppRevealNavigatorObserver? _observer;
  ScreenIdentifiable? _currentScreen;
  Route<dynamic>? _registeredRoute;

  void attachObserver(AppRevealNavigatorObserver observer) {
    _observer = observer;
  }

  void register(ScreenIdentifiable screen) {
    _currentScreen = screen is State ? null : screen;
    _registeredRoute = _observer?.currentRouteObject;
  }

  ScreenInfo resolve() {
    final routeStack = _observer?.routeStack ?? [];
    final routeName = _observer?.currentRoute ?? '/';
    final depth = routeStack.length;

    // 1. Explicit ScreenIdentifiable registration
    final registered = _currentScreen;
    final screen = registered is State
        ? null // Mounted states are resolved from the active tree below.
        : identical(_registeredRoute, _observer?.currentRouteObject)
            ? registered
            : null;
    if (screen != null) {
      return ScreenInfo(
        screenKey: screen.screenKey,
        screenTitle: screen.screenTitle,
        frameworkType: 'flutter',
        routeStack: routeStack,
        navigationDepth: depth,
        confidence: 1.0,
        source: 'explicit',
      );
    }

    // 2. Walk element tree for ScreenIdentifiable state
    final identifiable = _findScreenIdentifiable();
    if (identifiable != null) {
      return ScreenInfo(
        screenKey: identifiable.screenKey,
        screenTitle: identifiable.screenTitle,
        frameworkType: 'flutter',
        routeStack: routeStack,
        navigationDepth: depth,
        confidence: 1.0,
        source: 'explicit',
      );
    }

    // 3. Extract AppBar title for use as metadata and possible fallback
    final appBarTitle = _extractAppBarTitle();
    final stack = routeStack.isEmpty ? [routeName] : routeStack;

    // 4. Named route — derive from path segments
    if (_isUsableRouteName(routeName)) {
      final (key, title) = _deriveFromRoute(routeName);
      return ScreenInfo(
        screenKey: key,
        screenTitle: appBarTitle ?? title,
        frameworkType: 'flutter',
        routeStack: stack,
        navigationDepth: depth == 0 ? 1 : depth,
        confidence: 0.8,
        source: 'route',
        appBarTitle: appBarTitle,
      );
    }

    // 5. No usable route name but AppBar title available
    if (appBarTitle != null && appBarTitle.isNotEmpty) {
      final key = _normalizeToKey(appBarTitle);
      return ScreenInfo(
        screenKey: key,
        screenTitle: appBarTitle,
        frameworkType: 'flutter',
        routeStack: stack,
        navigationDepth: depth == 0 ? 1 : depth,
        confidence: 0.6,
        source: 'appbar',
        appBarTitle: appBarTitle,
      );
    }

    // 6. Fallback — best effort from whatever route string we have
    final (key, title) = _deriveFromRoute(routeName);
    return ScreenInfo(
      screenKey: key,
      screenTitle: title,
      frameworkType: 'flutter',
      routeStack: stack,
      navigationDepth: depth == 0 ? 1 : depth,
      confidence: 0.3,
      source: 'inferred',
    );
  }

  ScreenIdentifiable? _findScreenIdentifiable() {
    ScreenIdentifiable? found;
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return null;
    _visitElements(root, (element) {
      if (element.widget is ScreenIdentifiable) {
        found = element.widget as ScreenIdentifiable;
      }
      if (element is StatefulElement && element.state is ScreenIdentifiable) {
        found = element.state as ScreenIdentifiable;
      }
      return true;
    });
    return found;
  }

  /// Extract the title text from the topmost visible AppBar.
  String? _extractAppBarTitle() {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return null;

    String? title;
    _visitElements(root, (element) {
      if (element.widget is AppBar) {
        final titleWidget = (element.widget as AppBar).title;
        if (titleWidget is Text) {
          title = titleWidget.data ?? titleWidget.textSpan?.toPlainText();
        }
        return false; // The AppBar title is already available.
      }
      return true;
    });
    return title;
  }

  /// A route name is usable if it starts with / and isn't a runtime type string.
  static bool _isUsableRouteName(String name) {
    return name.startsWith('/') && !name.contains('<') && !name.contains('>');
  }

  /// Convert an AppBar title like "Product Management" into a dot-separated key.
  static String _normalizeToKey(String title) {
    return title
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'[^a-z0-9_]'), '');
  }

  void _visitElements(Element element, bool Function(Element) visitor) {
    if (!ElementInventory.isActive(element) || !visitor(element)) return;
    element.visitChildren((child) => _visitElements(child, visitor));
  }

  static (String, String) _deriveFromRoute(String routeName) {
    if (routeName == '/' || routeName.isEmpty) return ('home', 'Home');
    // '/auth/login' → 'auth.login', 'Login'
    final segments = routeName.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return ('home', 'Home');
    final key = segments.join('.');
    final title = _capitalize(segments.last.replaceAll(RegExp(r'[-_]'), ' '));
    return (key, title);
  }

  static String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s
        .split(' ')
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }
}
