import 'package:appreveal/src/elements/element_inventory.dart';
import 'package:appreveal/src/elements/element_resolver.dart';
import 'package:appreveal/src/interaction/interaction_engine.dart';
import 'package:appreveal/src/screen/navigator_observer.dart';
// Retain compatibility with Flutter versions before the UI package split.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> perform(
    WidgetTester tester, Future<void> Function() action) async {
  Object? error;
  var done = false;
  final future = action().then((_) {
    done = true;
  }, onError: (Object e) {
    error = e;
    done = true;
  });
  for (var i = 0; i < 40 && !done; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(done, isTrue, reason: 'Interaction must finish within two seconds');
  await future;
  if (error != null) throw error!;
}

Future<void> rejects(WidgetTester tester, Future<void> Function() action,
    Matcher matcher) async {
  Object? error;
  try {
    await perform(tester, action);
  } catch (e) {
    error = e;
  }
  expect(error, matcher);
}

void main() {
  final engine = InteractionEngine.shared;
  testWidgets('listed duplicate IDs tap the corresponding logical row',
      (tester) async {
    var selected = -1;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Column(children: [
      for (var i = 0; i < 3; i++)
        ListTile(
            title: const Text('Settings'),
            onTap: () {
              selected = i;
            }),
    ]))));
    final rows = ElementInventory.shared
        .listElements()
        .where((e) => e['type'] == 'listTile')
        .toList();
    expect(rows.length, 3);
    for (var i = 0; i < rows.length; i++) {
      await perform(
          tester, () => engine.tap(elementId: rows[i]['id'] as String));
      expect(selected, i);
    }
  });

  testWidgets('inactive IndexedStack children do not leak into inspection',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: IndexedStack(index: 1, children: [
      ElevatedButton(
          key: const ValueKey('inactive'),
          onPressed: () {},
          child: const Text('Inactive')),
      ElevatedButton(
          key: const ValueKey('active'),
          onPressed: () {},
          child: const Text('Active')),
    ]))));
    final ids = ElementInventory.shared.listElements().map((e) => e['id']);
    expect(ids, contains('active'));
    expect(ids, isNot(contains('inactive')));
    expect(ElementResolver.shared.resolve('inactive'), isNull);
  });

  testWidgets('scrollable variable-width TabBar selects the actual tab',
      (tester) async {
    var selected = -1;
    await tester.pumpWidget(MaterialApp(
        home: DefaultTabController(
      length: 3,
      child: Scaffold(
          appBar: AppBar(
              bottom: TabBar(
        isScrollable: true,
        onTap: (i) {
          selected = i;
        },
        tabs: const [
          Tab(text: 'A long first label'),
          Tab(text: 'B'),
          Tab(text: 'Target')
        ],
      ))),
    )));
    await perform(tester, () => engine.selectTab(index: 2));
    expect(selected, 2);
  });

  testWidgets('typing replaces selection and applies formatters and onChanged',
      (tester) async {
    final controller = TextEditingController(text: '1234');
    addTearDown(controller.dispose);
    var changed = '';
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TextField(
      key: const ValueKey('input'),
      controller: controller,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: (value) {
        changed = value;
      },
    ))));
    await tester.tap(find.byType(TextField));
    await tester.pump();
    controller.selection = const TextSelection(baseOffset: 3, extentOffset: 1);
    await perform(
        tester, () => engine.typeText(elementId: 'input', text: 'a9'));
    expect(controller.text, '194');
    expect(changed, '194');
    expect(controller.selection.baseOffset, 2);
    await perform(tester, () => engine.clearText(elementId: 'input'));
    expect(controller.text, '');
    expect(changed, '');
  });

  testWidgets('missing and noneditable targets never edit the focused field',
      (tester) async {
    final controller = TextEditingController(text: 'keep');
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Column(children: [
      TextField(key: const ValueKey('input'), controller: controller),
      ElevatedButton(
          key: const ValueKey('button'),
          onPressed: () {},
          child: const Text('Button')),
      const TextField(key: ValueKey('readonly'), readOnly: true),
      const TextField(key: ValueKey('disabled'), enabled: false),
    ]))));
    await tester.tap(find.byKey(const ValueKey('input')));
    await tester.pump();
    for (final id in ['missing', 'button', 'readonly', 'disabled']) {
      await rejects(tester, () => engine.typeText(elementId: id, text: 'wrong'),
          isA<Exception>());
      await rejects(
          tester, () => engine.clearText(elementId: id), isA<Exception>());
      expect(controller.text, 'keep');
    }
  });

  testWidgets('inactive and clipped targets are not listed or tapped',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Column(children: [
      Offstage(
          child: ElevatedButton(
              key: const ValueKey('hidden'),
              onPressed: () {
                tapped = true;
              },
              child: const Text('Hidden'))),
      SizedBox(
          height: 100,
          child: SingleChildScrollView(
              key: const ValueKey('list'),
              child: Column(children: [
                const SizedBox(height: 400),
                ElevatedButton(
                    key: const ValueKey('below'),
                    onPressed: () {
                      tapped = true;
                    },
                    child: const Text('Below')),
              ]))),
    ]))));
    final ids = ElementInventory.shared.listElements().map((e) => e['id']);
    expect(ids, isNot(contains('hidden')));
    expect(ids, isNot(contains('below')));
    expect(ElementResolver.shared.resolveByText('Hidden').isSuccess, false);
    await rejects(
        tester, () => engine.tap(elementId: 'below'), isA<Exception>());
    expect(tapped, false);
    await perform(tester, () => engine.scrollToElement(elementId: 'below'));
    await perform(tester, () => engine.tap(elementId: 'below'));
    expect(tapped, true);
  });

  testWidgets('blocked button and invalid coordinates fail without interaction',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Stack(children: [
      Center(
          child: ElevatedButton(
              key: const ValueKey('covered'),
              onPressed: () {
                tapped = true;
              },
              child: const Text('Covered'))),
      const Positioned.fill(
          child: AbsorbPointer(child: ColoredBox(color: Colors.white))),
    ]))));
    await rejects(
        tester, () => engine.tap(elementId: 'covered'), isA<Exception>());
    await expectLater(engine.tapPoint(x: -1, y: 10), throwsArgumentError);
    await expectLater(
        engine.tapPoint(x: double.nan, y: 10), throwsArgumentError);
    expect(tapped, false);
  });

  testWidgets('reverse scrolling uses visual direction and rejects wrong axis',
      (tester) async {
    final controller = ScrollController(initialScrollOffset: 400);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
      key: const ValueKey('list'),
      reverse: true,
      controller: controller,
      child: const SizedBox(height: 2000),
    ))));
    await perform(
        tester, () => engine.scroll(direction: 'down', containerId: 'list'));
    expect(controller.offset, 100);
    await rejects(
        tester,
        () => engine.scroll(direction: 'left', containerId: 'list'),
        isA<ArgumentError>());
    expect(controller.offset, 100);
  });

  testWidgets('RTL bottom navigation selects the requested logical tab',
      (tester) async {
    var selected = 0;
    await tester.pumpWidget(MaterialApp(
        home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
          bottomNavigationBar: BottomNavigationBar(
        currentIndex: selected,
        onTap: (index) {
          selected = index;
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings')
        ],
      )),
    )));
    await expectLater(engine.selectTab(index: -1), throwsArgumentError);
    await perform(tester, () => engine.selectTab(index: 1));
    expect(selected, 1);
  });

  testWidgets('modal dismissal refuses a page and back respects PopScope',
      (tester) async {
    final observer = AppRevealNavigatorObserver();
    final navigator = GlobalKey<NavigatorState>();
    engine.attachObserver(observer);
    await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [observer],
        home: const Scaffold(body: Text('Home'))));
    navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const PopScope(
            canPop: false, child: Scaffold(body: Text('Guarded')))));
    await tester.pumpAndSettle();
    await expectLater(engine.dismissModal(), throwsException);
    await rejects(tester, engine.navigateBack, isA<Exception>());
    expect(find.text('Guarded'), findsOneWidget);
    showDialog<void>(
        context: navigator.currentContext!,
        builder: (_) => const AlertDialog(title: Text('Dialog')));
    await tester.pumpAndSettle();
    await perform(tester, engine.dismissModal);
    await tester.pumpAndSettle();
    expect(find.text('Dialog'), findsNothing);
    expect(find.text('Guarded'), findsOneWidget);
  });
}
