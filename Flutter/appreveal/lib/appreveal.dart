// AppReveal — Debug-only in-app MCP framework for Flutter
// Use only in debug builds: if (kDebugMode) AppReveal.start();

library appreveal;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:package_info_plus/package_info_plus.dart';

import 'src/diagnostics/diagnostics_bridge.dart';
import 'src/discovery/mdns_advertiser.dart';
import 'src/interaction/interaction_engine.dart';
import 'src/mcp/mcp_server.dart';
import 'src/mcp/mcp_tools.dart';
import 'src/network/network_observer.dart';
import 'src/screen/navigator_observer.dart';
import 'src/screen/screen_identifiable.dart';
import 'src/screen/screen_resolver.dart';
import 'src/screenshot/screenshot_capture.dart';
import 'src/state/state_bridge.dart';
import 'src/webview/webview_bridge.dart';
import 'src/webview/webview_tools.dart';

// Re-export integration interfaces so callers only need to import appreveal.dart.
export 'src/screen/screen_identifiable.dart';
export 'src/state/state_bridge.dart'
    show StateProviding, NavigationProviding, FeatureFlagProviding;
export 'src/network/network_observer.dart'
    show NetworkObservable, NetworkTrafficObserver, CapturedRequest;
export 'src/screen/navigator_observer.dart' show AppRevealNavigatorObserver;

/// Main entry point for the AppReveal debug framework.
///
/// ## Setup
///
/// ```dart
/// void main() {
///   AppReveal.start();
///   runApp(AppReveal.wrap(const MyApp()));
/// }
/// ```
///
/// In your `MaterialApp`:
/// ```dart
/// MaterialApp(
///   navigatorObservers: [AppReveal.navigatorObserver],
/// )
/// ```
class AppReveal {
  AppReveal._();

  static final _server = MCPServer();

  /// Add to [MaterialApp.navigatorObservers] for automatic screen tracking.
  static final AppRevealNavigatorObserver navigatorObserver =
      AppRevealNavigatorObserver();

  /// Start the AppReveal MCP server and mDNS advertisement.
  /// No-ops silently in release mode — safe to call unconditionally.
  static void start({int port = 0}) {
    if (kReleaseMode) return;
    unawaited(_launch(port: port));
  }

  /// Stop the server and cancel mDNS advertisement.
  static Future<void> stop() async {
    await _server.stop();
    await MdnsAdvertiser.shared.unregister();
  }

  // ─── Registration ────────────────────────────────────────────────────────

  /// Declare the current screen's identity. Call from [State.initState] or
  /// on route changes on screens that implement [ScreenIdentifiable].
  static void registerScreen(ScreenIdentifiable screen) {
    if (kReleaseMode) return;
    ScreenResolver.shared.register(screen);
  }

  /// Register an app state provider for [get_state].
  static void registerStateProvider(StateProviding provider) {
    if (kReleaseMode) return;
    StateBridge.shared.registerStateProvider(provider);
  }

  /// Register a navigation provider for [get_navigation_stack].
  static void registerNavigationProvider(NavigationProviding provider) {
    if (kReleaseMode) return;
    StateBridge.shared.registerNavigationProvider(provider);
  }

  /// Register a feature flag provider for [get_feature_flags].
  static void registerFeatureFlagProvider(FeatureFlagProviding provider) {
    if (kReleaseMode) return;
    StateBridge.shared.registerFeatureFlagProvider(provider);
  }

  /// Register a network observable for [get_network_calls].
  static void registerNetworkObservable(NetworkObservable observable) {
    if (kReleaseMode) return;
    NetworkObserverService.shared.register(observable);
  }

  /// Register a [WebViewController] for WebView DOM inspection tools.
  ///
  /// ```dart
  /// final controller = WebViewController()
  ///   ..setJavaScriptMode(JavaScriptMode.unrestricted)
  ///   ..loadRequest(Uri.parse('https://example.com'));
  ///
  /// AppReveal.registerWebView('main', controller);
  /// ```
  static void registerWebView(String id, WebViewController controller,
      {String? title}) {
    if (kReleaseMode) return;
    WebViewBridge.shared.register(id, controller, title: title);
  }

  /// Unregister a previously registered [WebViewController].
  static void unregisterWebView(String id) {
    WebViewBridge.shared.unregister(id);
  }

  // ─── Wrap ────────────────────────────────────────────────────────────────

  /// Wrap your root widget to enable reliable screenshots.
  /// Adds a [RepaintBoundary] that [screenshot] will use.
  ///
  /// ```dart
  /// runApp(AppReveal.wrap(const MyApp()));
  /// ```
  static Widget wrap(Widget child) {
    if (kReleaseMode) return child;
    return RepaintBoundary(
      key: ScreenshotCapture.screenshotKey,
      child: child,
    );
  }

  // ─── Private ─────────────────────────────────────────────────────────────

  static Future<void> _launch({required int port}) async {
    // Wire observer into screen resolver and interaction engine
    ScreenResolver.shared.attachObserver(navigatorObserver);
    InteractionEngine.shared.attachObserver(navigatorObserver);

    // Install diagnostics interceptors
    DiagnosticsBridge.shared.install();

    // Register all 43 MCP tools
    registerBuiltInTools();
    registerWebViewTools();

    // Start HTTP server
    await _server.start(port: port);

    // Advertise via mDNS (use real bundle ID from PackageInfo)
    String bundleId = 'com.appreveal.app';
    String version = '0.4.0';
    try {
      final info = await PackageInfo.fromPlatform();
      bundleId = info.packageName;
      version = info.version;
    } catch (_) {}

    await MdnsAdvertiser.shared.register(
      port: _server.port,
      bundleId: bundleId,
      version: version,
    );
  }
}
