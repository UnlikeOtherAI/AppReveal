// Screen identity protocol — implement on State or Widget to declare a screen's identity.

/// Implement this mixin on a [StatefulWidget] or [State] to declare the current
/// screen's identity. AppReveal uses this for [get_screen] results when present.
///
/// Without this mixin, AppReveal auto-derives a screen key from the route name.
///
/// Example:
/// ```dart
/// class _LoginScreenState extends State<LoginScreen> with ScreenIdentifiable {
///   @override
///   String get screenKey => 'auth.login';
///   @override
///   String get screenTitle => 'Login';
/// }
/// ```
mixin ScreenIdentifiable {
  /// Stable dot-separated screen identifier, e.g. 'auth.login', 'orders.detail'.
  String get screenKey;

  /// Human-readable screen title.
  String get screenTitle;

  /// Optional additional debug metadata.
  Map<String, dynamic> get debugMetadata => const {};
}
