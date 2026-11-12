import 'package:appreveal/src/screen/navigator_observer.dart';
import 'package:appreveal/src/screen/screen_identifiable.dart';
import 'package:appreveal/src/screen/screen_resolver.dart';
// Retain compatibility with Flutter versions before the UI package split.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class Screen extends StatefulWidget {
  const Screen(this.name, {super.key});
  final String name;
  @override
  State<Screen> createState() => _ScreenState();
}

class _ScreenState extends State<Screen> with ScreenIdentifiable {
  @override
  String get screenKey => widget.name;
  @override
  String get screenTitle => widget.name;
  @override
  void initState() {
    super.initState();
    ScreenResolver.shared.register(this);
  }

  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: Text(widget.name)));
}

void main() {
  testWidgets('screen identity follows push, pop, and active tabs',
      (tester) async {
    final observer = AppRevealNavigatorObserver();
    final navigator = GlobalKey<NavigatorState>();
    ScreenResolver.shared.attachObserver(observer);
    await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [observer],
        home: const Screen('home')));
    navigator.currentState!.push(MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/detail'),
        builder: (_) => const Screen('detail')));
    await tester.pumpAndSettle();
    expect(ScreenResolver.shared.resolve().screenKey, 'detail');
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(ScreenResolver.shared.resolve().screenKey, 'home');
  });
  testWidgets('empty observer fallback does not throw clamp error',
      (tester) async {
    ScreenResolver.shared.attachObserver(AppRevealNavigatorObserver());
    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: Text('Plain'))));
    expect(ScreenResolver.shared.resolve().navigationDepth, 1);
  });
  test(
      'replace and remove operate on route identity, including duplicate names',
      () {
    final observer = AppRevealNavigatorObserver();
    Route<void> route(String name) => MaterialPageRoute<void>(
        settings: RouteSettings(name: name), builder: (_) => const SizedBox());
    final first = route('/same');
    final second = route('/same');
    final third = route('/third');
    observer.didPush(first, null);
    observer.didPush(second, first);
    observer.didPush(third, second);
    observer.didReplace(oldRoute: first, newRoute: route('/replacement'));
    expect(observer.routeStack, ['/replacement', '/same', '/third']);
    observer.didRemove(second, first);
    expect(observer.routeStack, ['/replacement', '/third']);
    expect(observer.currentRoute, '/third');
  });
}
