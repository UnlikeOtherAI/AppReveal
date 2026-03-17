// Provider interfaces and registry for app state, navigation, and feature flags.

/// Implement to expose app state to AppReveal's [get_state] tool.
abstract interface class StateProviding {
  Map<String, dynamic> snapshot();
}

/// Implement to expose navigation state to AppReveal's [get_navigation_stack] tool.
abstract interface class NavigationProviding {
  String get currentRoute;
  List<String> get navigationStack;
  List<String> get presentedModals;
}

/// Implement to expose feature flags to AppReveal's [get_feature_flags] tool.
abstract interface class FeatureFlagProviding {
  Map<String, dynamic> allFlags();
}

class StateBridge {
  static final shared = StateBridge._();
  StateBridge._();

  StateProviding? _stateProvider;
  NavigationProviding? _navigationProvider;
  FeatureFlagProviding? _featureFlagProvider;

  void registerStateProvider(StateProviding provider) {
    _stateProvider = provider;
  }

  void registerNavigationProvider(NavigationProviding provider) {
    _navigationProvider = provider;
  }

  void registerFeatureFlagProvider(FeatureFlagProviding provider) {
    _featureFlagProvider = provider;
  }

  Map<String, dynamic> getState() {
    final provider = _stateProvider;
    if (provider == null) return {'error': 'No StateProviding registered'};
    return provider.snapshot();
  }

  Map<String, dynamic> getNavigationStack() {
    final provider = _navigationProvider;
    if (provider == null) return {'error': 'No NavigationProviding registered'};
    return {
      'currentRoute': provider.currentRoute,
      'navigationStack': provider.navigationStack,
      'presentedModals': provider.presentedModals,
    };
  }

  Map<String, dynamic> getFeatureFlags() {
    final provider = _featureFlagProvider;
    if (provider == null) return {'error': 'No FeatureFlagProviding registered'};
    return provider.allFlags();
  }
}
