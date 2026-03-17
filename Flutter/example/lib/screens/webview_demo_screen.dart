import 'package:appreveal/appreveal.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class WebViewDemoScreen extends StatefulWidget {
  const WebViewDemoScreen({super.key});

  @override
  State<WebViewDemoScreen> createState() => _WebViewDemoScreenState();
}

class _WebViewDemoScreenState extends State<WebViewDemoScreen> with ScreenIdentifiable {
  late final WebViewController _controller;
  static const _webViewId = 'demo_webview';

  @override
  String get screenKey => 'webview.demo';

  @override
  String get screenTitle => 'WebView Demo';

  @override
  void initState() {
    super.initState();
    AppReveal.registerScreen(this);

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (url) {
          // Update title if possible
          _controller.getTitle().then((title) {
            AppReveal.registerWebView(_webViewId, _controller, title: title);
          });
        },
      ))
      ..loadRequest(Uri.parse('https://example.com'));

    AppReveal.registerWebView(_webViewId, _controller, title: 'Example');
  }

  @override
  void dispose() {
    AppReveal.unregisterWebView(_webViewId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WebView Demo'),
        actions: [
          IconButton(
            key: const ValueKey('webview.back'),
            icon: const Icon(Icons.arrow_back_ios),
            onPressed: () => _controller.goBack(),
          ),
          IconButton(
            key: const ValueKey('webview.forward'),
            icon: const Icon(Icons.arrow_forward_ios),
            onPressed: () => _controller.goForward(),
          ),
          IconButton(
            key: const ValueKey('webview.refresh'),
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller.reload(),
          ),
        ],
      ),
      body: WebViewWidget(
        key: const ValueKey('webview.content'),
        controller: _controller,
      ),
    );
  }
}
