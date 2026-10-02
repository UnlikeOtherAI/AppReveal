import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:appreveal/src/elements/element_inventory.dart';

/// Inspection must be read-only for the host app's element tree.
///
/// `MediaQuery.maybeOf(element)` / `Directionality.maybeOf(element)` are
/// `dependOnInheritedWidgetOfExactType` lookups: called from an MCP request
/// (outside any build) they register the INSPECTED element as a dependent. When
/// that element is itself the MediaQuery/Directionality element, it becomes its
/// own dependent — which no build can produce — and the next update of that
/// widget fails `InheritedElement.notifyClients` ("check that it really is our
/// descendant"). The build throws mid-update and the tree is left corrupt:
/// `_dependents.isEmpty` asserts follow and the host shows its error screen.
/// Observed in the Hugo POS during the PIN → Home transition while an agent
/// polled `get_elements`.
void main() {
  setUp(() => _BuildProbe.builds = 0);

  // `.last`: the test harness wraps the tree in its own View MediaQuery, so the
  // element under test is the innermost match.
  Element findElement<T extends Widget>(WidgetTester tester) =>
      tester.element(find.byType(T).last);

  Widget host({required EdgeInsets padding, TextDirection? direction}) {
    return Directionality(
      textDirection: direction ?? TextDirection.ltr,
      child: MediaQuery(
        data: MediaQueryData(padding: padding),
        child: const SizedBox(width: 10, height: 10),
      ),
    );
  }

  testWidgets(
      'reading safe-area insets of a MediaQuery element does not make it its '
      'own dependent (next MediaQuery update must not assert)', (tester) async {
    await tester.pumpWidget(host(padding: const EdgeInsets.only(top: 20)));

    final insets = ElementInventory.getSafeAreaInsets(
      findElement<MediaQuery>(tester),
    );
    expect(insets['top'], 20);

    await tester.pumpWidget(host(padding: const EdgeInsets.only(top: 44)));
    expect(tester.takeException(), isNull);
    expect(
      ElementInventory.getSafeAreaInsets(findElement<MediaQuery>(tester))['top'],
      44,
    );
  });

  testWidgets(
      'the safe-area layout guide of a MediaQuery element does not register a '
      'dependency either', (tester) async {
    await tester.pumpWidget(host(padding: const EdgeInsets.only(top: 20)));

    ElementInventory.getSafeAreaLayoutGuideFrame(findElement<MediaQuery>(tester));

    await tester.pumpWidget(host(padding: const EdgeInsets.only(top: 44)));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'inspection registers no dependency on an ancestor MediaQuery or '
      'Directionality', (tester) async {
    Widget tree(EdgeInsets padding, TextDirection direction) => MediaQuery(
          data: MediaQueryData(padding: padding),
          child: Directionality(
            textDirection: direction,
            child: const _BuildProbe(),
          ),
        );

    await tester.pumpWidget(tree(const EdgeInsets.only(top: 20), TextDirection.ltr));
    ElementInventory.getSafeAreaInsets(findElement<_BuildProbe>(tester));
    ElementInventory.getSafeAreaLayoutGuideFrame(findElement<_BuildProbe>(tester));
    final before = _BuildProbe.builds;

    // The probe is a const widget that reads neither MediaQuery nor
    // Directionality, so only a dependency registered by the inspection could
    // rebuild it when either value changes.
    await tester.pumpWidget(tree(const EdgeInsets.only(top: 44), TextDirection.ltr));
    expect(tester.takeException(), isNull);
    expect(_BuildProbe.builds, before, reason: 'MediaQuery dependency leaked');

    await tester.pumpWidget(tree(const EdgeInsets.only(top: 44), TextDirection.rtl));
    expect(tester.takeException(), isNull);
    expect(_BuildProbe.builds, before, reason: 'Directionality dependency leaked');
  });
}

class _BuildProbe extends StatelessWidget {
  const _BuildProbe();

  static int builds = 0;

  @override
  Widget build(BuildContext context) {
    builds++;
    return const SizedBox(width: 10, height: 10);
  }
}
