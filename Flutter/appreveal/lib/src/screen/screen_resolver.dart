// Resolves the currently active screen key, title, and metadata.

import 'package:flutter/widgets.dart';
import 'screen_identifiable.dart';
import 'navigator_observer.dart';

class ScreenInfo {
  final String screenKey;
  final String screenTitle;
  final String frameworkType;
  final List<String> routeStack;
  final int navigationDepth;
  final double confidence;

  const ScreenInfo({
    required this.screenKey,
    required this.screenTitle,
    required this.frameworkType,
    required this.routeStack,
    required this.navigationDepth,
    required this.confidence,
  });

  Map<String, dynamic> toMap() => {
    'screenKey': screenKey,
    'screenTitle': screenTitle,
    'frameworkType': frameworkType,
    'routeStack': routeStack,
    'navigationDepth': navigationDepth,
    'confidence': confidence,
  };
}

class ScreenResolver {
  static final shared = ScreenResolver._();
  ScreenResolver._();

  AppRevealNavigatorObserver? _observer;
  ScreenIdentifiable? _currentScreen;

  void attachObserver(AppRevealNavigatorObserver observer) {
    _observer = observer;
  }

  void register(ScreenIdentifiable screen) {
    _currentScreen = screen;
  }

  ScreenInfo resolve() {
    // Check for explicit ScreenIdentifiable registration
    final screen = _currentScreen;
    if (screen != null) {
      return ScreenInfo(
        screenKey: screen.screenKey,
        screenTitle: screen.screenTitle,
        frameworkType: 'flutter',
        routeStack: _observer?.routeStack ?? [],
        navigationDepth: _observer?.routeStack.length ?? 0,
        confidence: 1.0,
      );
    }

    // Walk element tree for ScreenIdentifiable state
    final identifiable = _findScreenIdentifiable();
    if (identifiable != null) {
      return ScreenInfo(
        screenKey: identifiable.screenKey,
        screenTitle: identifiable.screenTitle,
        frameworkType: 'flutter',
        routeStack: _observer?.routeStack ?? [],
        navigationDepth: _observer?.routeStack.length ?? 0,
        confidence: 1.0,
      );
    }

    // Auto-derive from route name
    final routeName = _observer?.currentRoute ?? '/';
    final (key, title) = _deriveFromRoute(routeName);
    return ScreenInfo(
      screenKey: key,
      screenTitle: title,
      frameworkType: 'flutter',
      routeStack: _observer?.routeStack ?? [routeName],
      navigationDepth: _observer?.routeStack.length ?? 1,
      confidence: 0.8,
    );
  }

  ScreenIdentifiable? _findScreenIdentifiable() {
    ScreenIdentifiable? found;
    final root = WidgetsBinding.instance.renderViewElement;
    if (root == null) return null;
    _visitElements(root, (element) {
      if (found != null) return false;
      if (element is StatefulElement && element.state is ScreenIdentifiable) {
        found = element.state as ScreenIdentifiable;
        return false;
      }
      return true;
    });
    return found;
  }

  void _visitElements(Element element, bool Function(Element) visitor) {
    if (!visitor(element)) return;
    element.visitChildren((child) => _visitElements(child, visitor));
  }

  static (String, String) _deriveFromRoute(String routeName) {
    if (routeName == '/' || routeName.isEmpty) return ('home', 'Home');
    // '/auth/login' → 'auth.login', 'Login'
    final segments = routeName
        .split('/')
        .where((s) => s.isNotEmpty)
        .toList();
    if (segments.isEmpty) return ('home', 'Home');
    final key = segments.join('.');
    final title = _capitalize(segments.last.replaceAll(RegExp(r'[-_]'), ' '));
    return (key, title);
  }

  static String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s.split(' ').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');
  }
}
