import 'package:appreveal/appreveal.dart';

class ExampleRouter implements NavigationProviding {
  static final instance = ExampleRouter._();
  ExampleRouter._();

  final _routeStack = <String>['/catalog'];
  final _modalStack = <String>[];

  void push(String route) {
    _routeStack.add(route);
  }

  void pop() {
    if (_routeStack.length > 1) _routeStack.removeLast();
  }

  void presentModal(String route) => _modalStack.add(route);
  void dismissModal() {
    if (_modalStack.isNotEmpty) _modalStack.removeLast();
  }

  @override
  String get currentRoute => _routeStack.last;

  @override
  List<String> get navigationStack => List.unmodifiable(_routeStack);

  @override
  List<String> get presentedModals => List.unmodifiable(_modalStack);
}
