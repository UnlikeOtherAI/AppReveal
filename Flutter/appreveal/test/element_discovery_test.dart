import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:appreveal/src/elements/element_inventory.dart';
import 'package:appreveal/src/elements/element_resolver.dart';

void main() {
  group('normalizeToId', () {
    test('converts spaces to underscores and lowercases', () {
      expect(
          ElementInventory.normalizeToId('Product Management'),
          'product_management');
    });

    test('strips non-alphanumeric characters', () {
      expect(ElementInventory.normalizeToId('Hello World!'), 'hello_world');
    });

    test('trims whitespace', () {
      expect(ElementInventory.normalizeToId('   spaces   '), 'spaces');
    });

    test('returns unnamed for empty input', () {
      expect(ElementInventory.normalizeToId(''), 'unnamed');
    });

    test('truncates long text to 40 chars', () {
      final long = 'a' * 60;
      expect(ElementInventory.normalizeToId(long).length, 40);
    });

    test('handles special characters', () {
      expect(ElementInventory.normalizeToId('Price: \$99.99'), 'price_9999');
    });
  });

  group('element discovery', () {
    testWidgets('discovers unkeyed ListTile with onTap', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              ListTile(
                title: const Text('Product Management'),
                onTap: () {},
              ),
            ],
          ),
        ),
      ));

      final elements = ElementInventory.shared.listElements();
      final listTile = elements.firstWhere(
        (e) => e['label'] == 'Product Management',
        orElse: () => <String, dynamic>{},
      );

      expect(listTile, isNotEmpty);
      expect(listTile['type'], 'listTile');
      expect(listTile['tappable'], true);
      expect(listTile['id'], 'product_management');
      expect(listTile['idSource'], 'text');
    });

    testWidgets('discovers keyed ListTile with explicit id', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              ListTile(
                key: const ValueKey('catalog.item.p1'),
                title: const Text('Wireless Headphones'),
                onTap: () {},
              ),
            ],
          ),
        ),
      ));

      final elements = ElementInventory.shared.listElements();
      final listTile = elements.firstWhere(
        (e) => e['id'] == 'catalog.item.p1',
        orElse: () => <String, dynamic>{},
      );

      expect(listTile, isNotEmpty);
      expect(listTile['type'], 'listTile');
      expect(listTile['label'], 'Wireless Headphones');
      expect(listTile['idSource'], 'explicit');
    });

    testWidgets('discovers unkeyed ElevatedButton', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () {},
              child: const Text('Submit Order'),
            ),
          ),
        ),
      ));

      final elements = ElementInventory.shared.listElements();
      final button = elements.firstWhere(
        (e) => e['label'] == 'Submit Order',
        orElse: () => <String, dynamic>{},
      );

      expect(button, isNotEmpty);
      expect(button['type'], 'button');
      expect(button['tappable'], true);
      expect(button['id'], 'submit_order');
      expect(button['idSource'], 'text');
    });

    testWidgets('discovers SwitchListTile', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SwitchListTile(
            title: const Text('Push Notifications'),
            value: true,
            onChanged: (_) {},
          ),
        ),
      ));

      final elements = ElementInventory.shared.listElements();
      final tile = elements.firstWhere(
        (e) => e['label'] == 'Push Notifications' && e['type'] == 'switchListTile',
        orElse: () => <String, dynamic>{},
      );

      expect(tile, isNotEmpty);
      expect(tile['tappable'], true);
      expect(tile['value'], 'true');
      expect(tile['idSource'], 'text');
    });

    testWidgets('discovers scrollable containers', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView(
            key: const ValueKey('my_list'),
            children: const [
              ListTile(title: Text('Item 1')),
              ListTile(title: Text('Item 2')),
            ],
          ),
        ),
      ));

      final elements = ElementInventory.shared.listElements();
      final scroll = elements.firstWhere(
        (e) => e['type'] == 'scrollView',
        orElse: () => <String, dynamic>{},
      );

      expect(scroll, isNotEmpty);
      expect(scroll['actions'], contains('scroll'));
    });

    testWidgets('deduplicates identical derived IDs', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              ListTile(
                title: const Text('Settings'),
                onTap: () {},
              ),
              ListTile(
                title: const Text('Settings'),
                onTap: () {},
              ),
            ],
          ),
        ),
      ));

      final elements = ElementInventory.shared.listElements();
      // Collect all entries whose ID starts with 'settings'
      final settingsEntries = elements
          .where((e) =>
              (e['id'] as String).startsWith('settings'))
          .toList();

      // Should have at least 2 listTile entries with unique IDs
      final listTileEntries = settingsEntries
          .where((e) => e['type'] == 'listTile')
          .toList();
      expect(listTileEntries.length, 2);
      expect(listTileEntries[0]['id'] != listTileEntries[1]['id'], true);
      // Both should have the correct label
      expect(listTileEntries[0]['label'], 'Settings');
      expect(listTileEntries[1]['label'], 'Settings');
    });

    testWidgets('discovers IconButton with tooltip', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [
              IconButton(
                icon: const Icon(Icons.search),
                tooltip: 'Search',
                onPressed: () {},
              ),
            ],
          ),
          body: const SizedBox(),
        ),
      ));

      final elements = ElementInventory.shared.listElements();
      final iconBtn = elements.firstWhere(
        (e) => e['label'] == 'Search' && e['type'] == 'iconButton',
        orElse: () => <String, dynamic>{},
      );

      expect(iconBtn, isNotEmpty);
      expect(iconBtn['tappable'], true);
    });

    testWidgets('discovers disabled button with enabled=false',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: null,
              child: const Text('Disabled'),
            ),
          ),
        ),
      ));

      final elements = ElementInventory.shared.listElements();
      final btn = elements.firstWhere(
        (e) => e['label'] == 'Disabled',
        orElse: () => <String, dynamic>{},
      );

      expect(btn, isNotEmpty);
      expect(btn['tappable'], true);
      expect(btn['enabled'], false);
    });
  });

  group('ElementResolver.resolve', () {
    testWidgets('resolves by ValueKey', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ElevatedButton(
            key: const ValueKey('submit_btn'),
            onPressed: () {},
            child: const Text('Submit'),
          ),
        ),
      ));

      final element = ElementResolver.shared.resolve('submit_btn');
      expect(element, isNotNull);
      expect(element!.widget.key, const ValueKey('submit_btn'));
    });

    testWidgets('resolves by derived text ID', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              ListTile(
                title: const Text('Product Management'),
                onTap: () {},
              ),
            ],
          ),
        ),
      ));

      final element =
          ElementResolver.shared.resolve('product_management');
      expect(element, isNotNull);
    });

    testWidgets('resolves by exact visible text', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              ListTile(
                title: const Text('Customer List'),
                onTap: () {},
              ),
            ],
          ),
        ),
      ));

      // Resolving by exact text should find the tappable ancestor
      final element = ElementResolver.shared.resolve('Customer List');
      expect(element, isNotNull);
    });
  });

  group('ElementResolver.resolveByText', () {
    testWidgets('finds single match and succeeds', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              ListTile(
                title: const Text('Product Management'),
                onTap: () {},
              ),
            ],
          ),
        ),
      ));

      final result =
          ElementResolver.shared.resolveByText('Product Management');
      expect(result.isSuccess, true);
      expect(result.element, isNotNull);
    });

    testWidgets('detects ambiguity with multiple matches', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              ListTile(
                title: const Text('Settings'),
                onTap: () {},
              ),
              ListTile(
                title: const Text('Settings'),
                onTap: () {},
              ),
            ],
          ),
        ),
      ));

      final result = ElementResolver.shared.resolveByText('Settings');
      expect(result.isSuccess, false);
      expect(result.candidates, isNotNull);
      expect(result.candidates!.length, 2);
    });

    testWidgets('resolves ambiguity with occurrence index', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              ListTile(
                title: const Text('Settings'),
                onTap: () {},
              ),
              ListTile(
                title: const Text('Settings'),
                onTap: () {},
              ),
            ],
          ),
        ),
      ));

      final result = ElementResolver.shared
          .resolveByText('Settings', occurrence: 1);
      expect(result.isSuccess, true);
    });

    testWidgets('contains mode matches partial text', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              ListTile(
                title: const Text('Product Management'),
                onTap: () {},
              ),
            ],
          ),
        ),
      ));

      final result = ElementResolver.shared
          .resolveByText('Product', matchMode: 'contains');
      expect(result.isSuccess, true);
    });

    testWidgets('reports non-tappable text', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('Just a label')),
        ),
      ));

      final result =
          ElementResolver.shared.resolveByText('Just a label');
      expect(result.isSuccess, false);
      expect(result.error, contains('no tappable ancestor'));
    });

    testWidgets('reports text not found', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: SizedBox()),
      ));

      final result =
          ElementResolver.shared.resolveByText('Nonexistent');
      expect(result.isSuccess, false);
      expect(result.error, contains('No element with text'));
    });
  });

  group('findTappableAncestor', () {
    testWidgets('finds a tappable ancestor for text inside ListTile',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListTile(
            title: const Text('Tap Me'),
            onTap: () {},
          ),
        ),
      ));

      // Find the Text element
      Element? textElement;
      void walk(Element el) {
        if (el.widget is Text && (el.widget as Text).data == 'Tap Me') {
          textElement = el;
          return;
        }
        el.visitChildren(walk);
      }
      final root = tester.binding.renderViewElement!;
      walk(root);

      expect(textElement, isNotNull);

      final tappable = ElementResolver.findTappableAncestor(textElement!);
      expect(tappable, isNotNull);
      // The tappable ancestor should be the ListTile or its internal
      // GestureDetector/InkWell — the exact widget depends on Flutter's
      // internal ListTile structure. The important thing is resolveByText
      // successfully resolves and taps it.
    });

    testWidgets('returns null for text with no tappable ancestor',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('Static label')),
        ),
      ));

      Element? textElement;
      void walk(Element el) {
        if (el.widget is Text && (el.widget as Text).data == 'Static label') {
          textElement = el;
          return;
        }
        el.visitChildren(walk);
      }
      final root = tester.binding.renderViewElement!;
      walk(root);

      expect(textElement, isNotNull);
      final tappable = ElementResolver.findTappableAncestor(textElement!);
      expect(tappable, isNull);
    });
  });
}
