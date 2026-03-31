// Flutter widget tree inspection — element listing and full tree dump.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class ElementInventory {
  static final shared = ElementInventory._();
  ElementInventory._();

  /// Walk all elements starting from [root], including overlay entries
  /// (drawers, dialogs, bottom sheets, tooltips) that sit above the route tree.
  /// The [visitor] returns false to stop traversal.
  static void visitAll(Element root, bool Function(Element) visitor) {
    final visited = <Element>{};
    final overlayEntries = <Element>[];
    bool stopped = false;

    void walk(Element element) {
      if (stopped || !visited.add(element)) return;
      if (element is StatefulElement && element.state is OverlayState) {
        element.visitChildren((theatre) {
          theatre.visitChildren((entry) => overlayEntries.add(entry));
        });
      }
      if (!visitor(element)) {
        stopped = true;
        return;
      }
      element.visitChildren(walk);
    }

    walk(root);

    for (final entry in overlayEntries) {
      if (stopped) break;
      walk(entry);
    }
  }

  /// List all interactive/identified elements on the current screen.
  List<Map<String, dynamic>> listElements() {
    final root = WidgetsBinding.instance.renderViewElement;
    if (root == null) return [];

    final results = <Map<String, dynamic>>[];
    final seen = <String>{};
    final visited = <Element>{};
    _collectElements(root, results, seen, visited);

    for (final entry in overlayEntryElements(root)) {
      _collectElements(entry, results, seen, visited);
    }

    return results;
  }

  /// Full widget tree dump for get_view_tree.
  List<Map<String, dynamic>> dumpWidgetTree({int maxDepth = 50}) {
    final root = WidgetsBinding.instance.renderViewElement;
    if (root == null) return [];
    final nodes = <Map<String, dynamic>>[];
    final visited = <Element>{};
    _dumpElement(root, 0, maxDepth, nodes, visited);

    for (final entry in overlayEntryElements(root)) {
      _dumpElement(entry, 0, maxDepth, nodes, visited);
    }

    return nodes;
  }

  /// Find an element by ValueKey<String> or semantic label.
  /// For enhanced resolution (text matching, derived IDs), use ElementResolver.
  Element? findElement(String id) {
    final root = WidgetsBinding.instance.renderViewElement;
    if (root == null) return null;
    final visited = <Element>{};
    final found = _findById(root, id, visited);
    if (found != null) return found;

    for (final entry in overlayEntryElements(root)) {
      final result = _findById(entry, id, visited);
      if (result != null) return result;
    }

    return null;
  }

  // ─── Public Helpers ──────────────────────────────────────────────────────

  /// Collect overlay-entry elements from [root]. Overlay entries host
  /// drawers, dialogs, bottom sheets, and tooltips above the route tree.
  List<Element> overlayEntryElements(Element root) {
    final entries = <Element>[];
    void walk(Element el) {
      if (el is StatefulElement && el.state is OverlayState) {
        el.visitChildren((theatre) {
          theatre.visitChildren((entry) => entries.add(entry));
        });
      }
      el.visitChildren(walk);
    }
    walk(root);
    return entries;
  }

  /// Get frame string "x,y,width,height" for an element's render box.
  static String? getFrame(Element element) {
    try {
      final renderObject = element.renderObject;
      if (renderObject is! RenderBox) return null;
      if (!renderObject.attached) return null;
      final offset = renderObject.localToGlobal(Offset.zero);
      final size = renderObject.size;
      if (size.isEmpty) return null;
      return '${offset.dx.round()},${offset.dy.round()},${size.width.round()},${size.height.round()}';
    } catch (_) {
      return null;
    }
  }

  /// Extract the primary visible text from an element.
  /// Prefers direct property access (ListTile.title, Button.child) over tree walking.
  static String? extractPrimaryText(Element element) {
    final widget = element.widget;
    final direct = _extractDirectLabel(widget);
    if (direct != null && direct.trim().isNotEmpty) return direct;
    return extractFirstText(element);
  }

  /// Extract first visible Text from an element's descendants.
  static String? extractFirstText(Element element) {
    String? result;
    void walk(Element el) {
      if (result != null) return;
      final w = el.widget;
      if (w is Text) {
        final t = w.data;
        if (t != null && t.trim().isNotEmpty) {
          result = t;
          return;
        }
        final span = w.textSpan;
        if (span != null) {
          final plain = span.toPlainText();
          if (plain.trim().isNotEmpty) {
            result = plain;
            return;
          }
        }
      }
      el.visitChildren(walk);
    }
    element.visitChildren(walk);
    return result;
  }

  /// Normalize text into a stable, deterministic ID string.
  static String normalizeToId(String text) {
    var normalized = text
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'[^a-z0-9_]'), '');
    if (normalized.length > 40) normalized = normalized.substring(0, 40);
    return normalized.isEmpty ? 'unnamed' : normalized;
  }

  // ─── Private ─────────────────────────────────────────────────────────────

  /// Try to extract a label directly from a widget's title/child property.
  static String? _extractDirectLabel(Widget widget) {
    Widget? labelWidget;
    if (widget is ListTile) {
      labelWidget = widget.title;
    } else if (widget is SwitchListTile) {
      labelWidget = widget.title;
    } else if (widget is CheckboxListTile) {
      labelWidget = widget.title;
    } else if (widget is ExpansionTile) {
      labelWidget = widget.title;
    } else if (widget is ButtonStyleButton) {
      labelWidget = widget.child;
    }

    if (labelWidget is Text) {
      return labelWidget.data ?? labelWidget.textSpan?.toPlainText();
    }
    return null;
  }

  void _collectElements(
    Element element,
    List<Map<String, dynamic>> results,
    Set<String> seen,
    Set<Element> visited,
  ) {
    if (!visited.add(element)) return;

    final info = _describeInteractive(element);
    if (info != null) {
      // Skip raw tappables (InkWell/GestureDetector) that live inside a
      // logical tappable parent — the parent is already surfaced.
      if (info['type'] == 'tappable' &&
          info['idSource'] != 'explicit' &&
          _hasLogicalTappableAncestor(element)) {
        element.visitChildren(
            (child) => _collectElements(child, results, seen, visited));
        return;
      }

      var id = info['id'] as String;
      if (seen.contains(id)) {
        // Append suffix index to make unique
        for (int i = 1; i < 100; i++) {
          final deduped = '${id}_$i';
          if (!seen.contains(deduped)) {
            id = deduped;
            info['id'] = id;
            break;
          }
        }
      }
      if (!seen.contains(id)) {
        seen.add(id);
        results.add(info);
      }
    }

    // Standalone Semantics nodes
    final widget = element.widget;
    if (widget is Semantics) {
      final label = widget.properties.label;
      if (label != null && label.isNotEmpty && !seen.contains(label)) {
        final frame = getFrame(element);
        if (frame != null) {
          seen.add(label);
          results.add({
            'id': label,
            'type': 'semantic',
            'label': label,
            'value': widget.properties.value ?? '',
            'enabled': !(widget.properties.enabled == false),
            'visible': true,
            'tappable': widget.properties.onTap != null,
            'frame': frame,
            'actions': widget.properties.onTap != null ? ['tap'] : [],
            'idSource': 'semantics',
          });
        }
      }
    }

    element.visitChildren(
        (child) => _collectElements(child, results, seen, visited));
  }

  /// Check if an InkWell/GestureDetector is inside a logical tappable parent.
  static bool _hasLogicalTappableAncestor(Element element) {
    bool found = false;
    int depth = 0;
    element.visitAncestorElements((ancestor) {
      depth++;
      if (depth > 10) return false;
      final w = ancestor.widget;
      if (w is Scaffold || w is MaterialApp) return false;
      if (w is ListTile ||
          w is SwitchListTile ||
          w is CheckboxListTile ||
          w is ExpansionTile ||
          w is ButtonStyleButton ||
          w is IconButton ||
          w is FloatingActionButton ||
          w is PopupMenuButton) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }

  Map<String, dynamic>? _describeInteractive(Element element) {
    final widget = element.widget;
    final frame = getFrame(element);
    if (frame == null) return null;

    String? explicitId;
    String type = 'view';
    bool tappable = false;
    bool enabled = true;
    String? label;
    String? value;
    List<String> actions = [];
    String idSource = 'derived';

    // 1. Explicit ValueKey<String>
    final key = widget.key;
    if (key is ValueKey<String>) {
      explicitId = key.value;
      idSource = 'explicit';
    }

    // 2. Widget type detection
    if (widget is ButtonStyleButton) {
      type = 'button';
      tappable = true;
      enabled = widget.onPressed != null;
      actions = ['tap'];
      final child = widget.child;
      if (child is Text) label = child.data;
    } else if (widget is IconButton) {
      type = 'iconButton';
      tappable = true;
      enabled = widget.onPressed != null;
      actions = ['tap'];
      label = widget.tooltip;
      if (label == null) {
        final icon = widget.icon;
        if (icon is Icon) label = icon.semanticLabel;
      }
    } else if (widget is FloatingActionButton) {
      type = 'floatingActionButton';
      tappable = true;
      enabled = widget.onPressed != null;
      actions = ['tap'];
      label = widget.tooltip;
    } else if (widget is GestureDetector) {
      if (widget.onTap != null) {
        type = 'tappable';
        tappable = true;
        actions = ['tap'];
      }
    } else if (widget is InkWell) {
      if (widget.onTap != null) {
        type = 'tappable';
        tappable = true;
        actions = ['tap'];
      }
    } else if (widget is TextField) {
      type = 'textField';
      tappable = true;
      label = widget.decoration?.labelText ?? widget.decoration?.hintText;
      actions = ['tap', 'type', 'clear'];
    } else if (widget is TextFormField) {
      type = 'textField';
      tappable = true;
      actions = ['tap', 'type', 'clear'];
    } else if (widget is Checkbox) {
      type = 'checkbox';
      tappable = true;
      enabled = widget.onChanged != null;
      value = widget.value?.toString();
      actions = ['tap'];
    } else if (widget is Switch) {
      type = 'switch';
      tappable = true;
      enabled = widget.onChanged != null;
      value = widget.value.toString();
      actions = ['tap'];
    } else if (widget is Radio) {
      type = 'radio';
      tappable = true;
      enabled = widget.onChanged != null;
      actions = ['tap'];
    } else if (widget is DropdownButton) {
      type = 'dropdown';
      tappable = true;
      enabled = widget.onChanged != null;
      actions = ['tap'];
    } else if (widget is DropdownButtonFormField) {
      type = 'dropdown';
      tappable = true;
      actions = ['tap'];
    } else if (widget is ListTile) {
      if (widget.onTap != null || explicitId != null) {
        type = 'listTile';
        tappable = widget.onTap != null;
        enabled = widget.enabled;
        actions = widget.onTap != null ? ['tap'] : [];
      }
      final titleWidget = widget.title;
      if (titleWidget is Text) label = titleWidget.data;
    } else if (widget is SwitchListTile) {
      type = 'switchListTile';
      tappable = true;
      enabled = widget.onChanged != null;
      value = widget.value.toString();
      actions = ['tap'];
      final titleWidget = widget.title;
      if (titleWidget is Text) label = titleWidget.data;
    } else if (widget is CheckboxListTile) {
      type = 'checkboxListTile';
      tappable = true;
      enabled = widget.onChanged != null;
      value = widget.value?.toString() ?? 'null';
      actions = ['tap'];
      final titleWidget = widget.title;
      if (titleWidget is Text) label = titleWidget.data;
    } else if (widget is ExpansionTile) {
      type = 'expansionTile';
      tappable = true;
      actions = ['tap'];
      final titleWidget = widget.title;
      if (titleWidget is Text) label = titleWidget.data;
    } else if (widget is PopupMenuButton) {
      type = 'popupMenuButton';
      tappable = true;
      enabled = widget.enabled;
      actions = ['tap'];
      label = widget.tooltip;
    } else if (widget is BottomNavigationBar) {
      type = 'tabBar';
      actions = ['selectTab'];
    } else if (widget is TabBar) {
      type = 'tabBar';
      actions = ['selectTab'];
    } else if (widget is NavigationBar) {
      type = 'tabBar';
      actions = ['selectTab'];
    } else if (widget is ScrollView) {
      // Catches ListView, GridView, CustomScrollView
      type = 'scrollView';
      actions = ['scroll'];
    } else if (widget is SingleChildScrollView) {
      type = 'scrollView';
      actions = ['scroll'];
    }

    // 3. Extract visible text if label not yet set
    if ((label == null || label.isEmpty) && type != 'scrollView') {
      label = extractFirstText(element);
    }

    // 4. Only emit if interactive, scrollable, tab bar, or has explicit ID
    if (explicitId == null &&
        !tappable &&
        type != 'scrollView' &&
        type != 'tabBar') {
      return null;
    }

    // 5. Derive ID from best available source
    String id;
    if (explicitId != null) {
      id = explicitId;
      idSource = 'explicit';
    } else if (label != null && label.isNotEmpty) {
      id = normalizeToId(label);
      idSource = 'text';
    } else {
      id = '${type}_${frame.hashCode.abs() % 10000}';
      idSource = 'derived';
    }

    return {
      'id': id,
      'type': type,
      'label': label ?? '',
      'value': value ?? '',
      'enabled': enabled,
      'visible': true,
      'tappable': tappable,
      'frame': frame,
      'actions': actions,
      'idSource': idSource,
    };
  }

  void _dumpElement(Element element, int depth, int maxDepth,
      List<Map<String, dynamic>> nodes, Set<Element> visited) {
    if (depth > maxDepth) return;
    if (!visited.add(element)) return;

    final widget = element.widget;
    final node = <String, dynamic>{
      'depth': depth,
      'type': widget.runtimeType.toString(),
    };

    final key = widget.key;
    if (key is ValueKey<String>) node['id'] = key.value;
    if (key != null) node['key'] = key.toString();

    final frame = getFrame(element);
    if (frame != null) node['frame'] = frame;

    // Widget-specific properties
    if (widget is Text) {
      node['text'] = widget.data ?? '';
    } else if (widget is TextField) {
      if (widget.decoration?.hintText != null) {
        node['placeholder'] = widget.decoration!.hintText;
      }
      if (widget.decoration?.labelText != null) {
        node['label'] = widget.decoration!.labelText;
      }
    } else if (widget is Checkbox) {
      node['checked'] = widget.value?.toString();
    } else if (widget is Switch) {
      node['value'] = widget.value.toString();
    } else if (widget is Semantics) {
      final props = widget.properties;
      if (props.label != null) node['semanticLabel'] = props.label;
    }

    nodes.add(node);
    element.visitChildren(
        (child) => _dumpElement(child, depth + 1, maxDepth, nodes, visited));
  }

  Element? _findById(Element element, String id, Set<Element> visited) {
    if (!visited.add(element)) return null;
    final key = element.widget.key;
    if (key is ValueKey<String> && key.value == id) return element;
    if (element.widget is Semantics) {
      final label = (element.widget as Semantics).properties.label;
      if (label == id) return element;
    }
    Element? found;
    element.visitChildren((child) {
      if (found == null) found = _findById(child, id, visited);
    });
    return found;
  }
}
