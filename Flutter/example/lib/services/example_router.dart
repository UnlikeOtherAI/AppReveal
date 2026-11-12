import 'package:appreveal/appreveal.dart';

/// Report the Navigator that the example actually uses.
class ExampleRouter implements NavigationProviding {
  static final instance = ExampleRouter._();
  ExampleRouter._();

  @override
  String get currentRoute => AppReveal.navigatorObserver.currentRoute;

  @override
  List<String> get navigationStack => AppReveal.navigatorObserver.routeStack;

  @override
  List<String> get presentedModals => AppReveal.navigatorObserver.presentedModals;
}
