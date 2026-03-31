// Text-based element resolution and enhanced element lookup.

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

import 'element_inventory.dart';

/// Result of a text-based element resolution.
class TextResolveResult {
  final Element? element;
  final String? error;
  final List<Map<String, dynamic>>? candidates;

  TextResolveResult._(this.element, this.error, this.candidates);

  factory TextResolveResult.success(Element element) =>
      TextResolveResult._(element, null, null);

  factory TextResolveResult.error(String message,
          {List<Map<String, dynamic>>? candidates}) =>
      TextResolveResult._(null, message, candidates);

  factory TextResolveResult.ambiguous(List<Map<String, dynamic>> candidates) =>
      TextResolveResult._(
        null,
        'Ambiguous: ${candidates.length} tappable elements match. '
        'Specify occurrence (0-${candidates.length - 1}) to disambiguate.',
        candidates,
      );

  bool get isSuccess => element != null;
}

class ElementResolver {
  static final shared = ElementResolver._();
  ElementResolver._();

  /// Resolve an element by ID with enhanced fallback chain:
  /// 1. Exact ValueKey<String>
  /// 2. Exact Semantics label
  /// 3. Derived ID match on interactive element (normalized text equals normalized input)
  /// 4. Exact visible text on a Text widget → nearest tappable ancestor
  /// 5. Normalized visible text on a Text widget → nearest tappable ancestor
  Element? resolve(String id) {
    final root = WidgetsBinding.instance.renderViewElement;
    if (root == null) return null;

    final normalizedId = ElementInventory.normalizeToId(id);
    Element? keyMatch;
    Element? semanticsMatch;
    Element? derivedMatch;
    Element? textMatch;
    Element? normalizedMatch;
    final visited = <Element>{};

    void walk(Element element) {
      if (keyMatch != null || !visited.add(element)) return;
      final widget = element.widget;

      // Priority 1: Exact ValueKey<String>
      final key = widget.key;
      if (key is ValueKey<String> && key.value == id) {
        keyMatch = element;
        return;
      }

      // Priority 2: Exact Semantics label
      if (semanticsMatch == null && widget is Semantics) {
        final label = widget.properties.label;
        if (label == id) {
          semanticsMatch = element;
        }
      }

      // Priority 3: Derived ID match on interactive widget
      if (derivedMatch == null && _isInteractiveWidget(widget)) {
        final text = ElementInventory.extractPrimaryText(element);
        if (text != null &&
            ElementInventory.normalizeToId(text) == normalizedId) {
          derivedMatch = element;
        }
      }

      // Priority 4: Exact text node → tappable ancestor
      if (textMatch == null && widget is Text) {
        final textData = widget.data ?? widget.textSpan?.toPlainText();
        if (textData == id) {
          final tappable = findTappableAncestor(element);
          if (tappable != null) {
            textMatch = tappable;
          }
        }
      }

      // Priority 5: Normalized text → tappable ancestor
      if (normalizedMatch == null && widget is Text) {
        final textData = widget.data ?? widget.textSpan?.toPlainText();
        if (textData != null &&
            ElementInventory.normalizeToId(textData) == normalizedId) {
          final tappable = findTappableAncestor(element);
          if (tappable != null) {
            normalizedMatch = tappable;
          }
        }
      }

      element.visitChildren(walk);
    }

    walk(root);
    if (keyMatch == null) {
      for (final entry
          in ElementInventory.shared.overlayEntryElements(root)) {
        walk(entry);
        if (keyMatch != null) break;
      }
    }

    return keyMatch ??
        semanticsMatch ??
        derivedMatch ??
        textMatch ??
        normalizedMatch;
  }

  /// Find tappable element(s) by visible text.
  TextResolveResult resolveByText(
    String text, {
    String matchMode = 'exact',
    int? occurrence,
  }) {
    final root = WidgetsBinding.instance.renderViewElement;
    if (root == null) {
      return TextResolveResult.error('No root element');
    }

    final matches = <_TextMatch>[];
    final tappablesSeen = <Element>{};
    final visited = <Element>{};

    void walk(Element element) {
      if (!visited.add(element)) return;
      String? textContent;
      final widget = element.widget;
      if (widget is Text) {
        textContent = widget.data ?? widget.textSpan?.toPlainText();
      }
      if (textContent != null && _textMatches(textContent, text, matchMode)) {
        final tappable = findTappableAncestor(element);
        if (tappable != null && tappablesSeen.add(tappable)) {
          matches.add(_TextMatch(
            tappableElement: tappable,
            matchedText: textContent,
            frame: ElementInventory.getFrame(tappable),
            type: _widgetTypeName(tappable.widget),
          ));
        }
      }
      element.visitChildren(walk);
    }

    walk(root);
    for (final entry in ElementInventory.shared.overlayEntryElements(root)) {
      walk(entry);
    }

    if (matches.isEmpty) {
      final hasText = _hasTextAnywhere(root, text, matchMode);
      if (hasText) {
        return TextResolveResult.error(
          'Found text "$text" but it has no tappable ancestor. '
          'The text is visible but not inside a tappable widget.',
        );
      }
      return TextResolveResult.error(
        'No element with text "$text" found on the current screen.',
      );
    }

    if (matches.length == 1) {
      return TextResolveResult.success(matches[0].tappableElement);
    }

    // Multiple matches
    if (occurrence != null) {
      if (occurrence < 0 || occurrence >= matches.length) {
        return TextResolveResult.error(
          'Occurrence $occurrence out of range (0-${matches.length - 1})',
          candidates: matches.map((m) => m.toCandidate()).toList(),
        );
      }
      return TextResolveResult.success(matches[occurrence].tappableElement);
    }

    return TextResolveResult.ambiguous(
      matches.map((m) => m.toCandidate()).toList(),
    );
  }

  // ─── Static Helpers ──────────────────────────────────────────────────────

  /// Find the nearest tappable ancestor of [element] (or the element itself).
  /// Prefers logical tappables (ListTile, buttons) over raw InkWell/GestureDetector.
  static Element? findTappableAncestor(Element element) {
    // Check self first
    if (_canReceiveTap(element.widget)) return element;

    Element? rawTappable;
    Element? logicalTappable;
    int depth = 0;

    element.visitAncestorElements((ancestor) {
      depth++;
      if (depth > 50) return false;

      final w = ancestor.widget;
      // Stop at page/route boundaries
      if (w is Scaffold || w is MaterialApp) return false;

      if (_isLogicalTappable(w)) {
        logicalTappable = ancestor;
        return false;
      }
      if ((w is InkWell && w.onTap != null) ||
          (w is GestureDetector && w.onTap != null)) {
        rawTappable ??= ancestor;
      }
      return true;
    });

    return logicalTappable ?? rawTappable;
  }

  // ─── Private ─────────────────────────────────────────────────────────────

  /// Whether a widget can actually receive a tap right now.
  static bool _canReceiveTap(Widget w) {
    if (w is ButtonStyleButton) return w.onPressed != null;
    if (w is IconButton) return w.onPressed != null;
    if (w is FloatingActionButton) return w.onPressed != null;
    if (w is GestureDetector) return w.onTap != null;
    if (w is InkWell) return w.onTap != null;
    if (w is ListTile) return w.onTap != null;
    if (w is SwitchListTile) return w.onChanged != null;
    if (w is CheckboxListTile) return w.onChanged != null;
    if (w is ExpansionTile) return true;
    if (w is PopupMenuButton) return w.enabled;
    if (w is Checkbox) return w.onChanged != null;
    if (w is Switch) return w.onChanged != null;
    if (w is Radio) return w.onChanged != null;
    if (w is DropdownButton) return w.onChanged != null;
    return false;
  }

  /// Whether a widget is any interactive type (for derived ID matching).
  static bool _isInteractiveWidget(Widget widget) {
    return _canReceiveTap(widget) ||
        widget is TextField ||
        widget is TextFormField;
  }

  /// Whether a widget is a "logical" tappable (user-facing composite widget)
  /// as opposed to a raw InkWell/GestureDetector.
  static bool _isLogicalTappable(Widget w) {
    if (w is ListTile) return w.onTap != null;
    if (w is SwitchListTile) return w.onChanged != null;
    if (w is CheckboxListTile) return w.onChanged != null;
    if (w is ExpansionTile) return true;
    if (w is ButtonStyleButton) return w.onPressed != null;
    if (w is IconButton) return w.onPressed != null;
    if (w is FloatingActionButton) return w.onPressed != null;
    if (w is PopupMenuButton) return w.enabled;
    return false;
  }

  static bool _textMatches(String content, String query, String mode) {
    return switch (mode) {
      'contains' => content.toLowerCase().contains(query.toLowerCase()),
      _ => content == query,
    };
  }

  static String _widgetTypeName(Widget w) {
    if (w is ListTile) return 'listTile';
    if (w is SwitchListTile) return 'switchListTile';
    if (w is CheckboxListTile) return 'checkboxListTile';
    if (w is ExpansionTile) return 'expansionTile';
    if (w is ButtonStyleButton) return 'button';
    if (w is IconButton) return 'iconButton';
    if (w is FloatingActionButton) return 'floatingActionButton';
    if (w is GestureDetector || w is InkWell) return 'tappable';
    return 'view';
  }

  bool _hasTextAnywhere(Element root, String text, String matchMode) {
    bool found = false;
    final visited = <Element>{};
    void walk(Element el) {
      if (found || !visited.add(el)) return;
      if (el.widget is Text) {
        final t = (el.widget as Text).data ??
            (el.widget as Text).textSpan?.toPlainText();
        if (t != null && _textMatches(t, text, matchMode)) {
          found = true;
          return;
        }
      }
      el.visitChildren(walk);
    }
    walk(root);
    return found;
  }
}

class _TextMatch {
  final Element tappableElement;
  final String matchedText;
  final String? frame;
  final String type;

  _TextMatch({
    required this.tappableElement,
    required this.matchedText,
    this.frame,
    required this.type,
  });

  Map<String, dynamic> toCandidate() => {
        'text': matchedText,
        'type': type,
        'frame': frame ?? '',
      };
}
