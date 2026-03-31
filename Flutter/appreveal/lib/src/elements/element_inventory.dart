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

    // Overlay-hosted widgets (drawers, dialogs, bottom sheets, tooltips)
    // may not be reached by the standard element tree walk.
    for (final entry in _overlayEntryElements(root)) {
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

    for (final entry in _overlayEntryElements(root)) {
      _dumpElement(entry, 0, maxDepth, nodes, visited);
    }

    return nodes;
  }

  /// Find an element by ValueKey<String> or semantic label.
  Element? findElement(String id) {
    final root = WidgetsBinding.instance.renderViewElement;
    if (root == null) return null;
    final visited = <Element>{};
    final found = _findById(root, id, visited);
    if (found != null) return found;

    for (final entry in _overlayEntryElements(root)) {
      final result = _findById(entry, id, visited);
      if (result != null) return result;
    }

    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────

  /// Collect overlay-entry elements from [root]. Overlay entries host
  /// drawers, dialogs, bottom sheets, and tooltips above the route tree.
  List<Element> _overlayEntryElements(Element root) {
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

  void _collectElements(
    Element element,
    List<Map<String, dynamic>> results,
    Set<String> seen,
    Set<Element> visited,
  ) {
    if (!visited.add(element)) return;

    final widget = element.widget;
    final info = _describeInteractive(element);

    if (info != null) {
      final id = info['id'] as String;
      if (!seen.contains(id)) {
        seen.add(id);
        results.add(info);
      }
    }

    // Walk Semantics nodes even if the widget itself isn't interactive
    if (widget is Semantics) {
      final label = widget.properties.label;
      if (label != null && label.isNotEmpty && !seen.contains(label)) {
        final frame = _getFrame(element);
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
          });
        }
      }
    }

    element.visitChildren((child) => _collectElements(child, results, seen, visited));
  }

  Map<String, dynamic>? _describeInteractive(Element element) {
    final widget = element.widget;
    final frame = _getFrame(element);
    if (frame == null) return null;

    String? id;
    String type = 'view';
    bool tappable = false;
    String? label;
    String? value;
    List<String> actions = [];

    // Explicit element ID via ValueKey<String>
    final key = widget.key;
    if (key is ValueKey<String>) {
      id = key.value;
    }

    if (widget is ElevatedButton || widget is TextButton || widget is OutlinedButton ||
        widget is FilledButton) {
      type = 'button';
      tappable = true;
      actions = ['tap'];
    } else if (widget is IconButton) {
      type = 'iconButton';
      tappable = true;
      actions = ['tap'];
    } else if (widget is FloatingActionButton) {
      type = 'floatingActionButton';
      tappable = true;
      actions = ['tap'];
    } else if (widget is GestureDetector) {
      final gd = widget as GestureDetector;
      if (gd.onTap != null) {
        type = 'tappable';
        tappable = true;
        actions = ['tap'];
      }
    } else if (widget is InkWell) {
      final iw = widget as InkWell;
      if (iw.onTap != null) {
        type = 'tappable';
        tappable = true;
        actions = ['tap'];
      }
    } else if (widget is TextField) {
      type = 'textField';
      tappable = true;
      label = (widget as TextField).decoration?.labelText ??
          (widget as TextField).decoration?.hintText;
      actions = ['tap', 'type', 'clear'];
    } else if (widget is TextFormField) {
      type = 'textField';
      tappable = true;
      actions = ['tap', 'type', 'clear'];
    } else if (widget is Checkbox) {
      type = 'checkbox';
      tappable = true;
      value = (widget as Checkbox).value?.toString();
      actions = ['tap'];
    } else if (widget is Switch) {
      type = 'switch';
      tappable = true;
      value = (widget as Switch).value.toString();
      actions = ['tap'];
    } else if (widget is Radio) {
      type = 'radio';
      tappable = true;
      actions = ['tap'];
    } else if (widget is DropdownButton || widget is DropdownButtonFormField) {
      type = 'dropdown';
      tappable = true;
      actions = ['tap'];
    } else if (widget is ListTile) {
      final lt = widget as ListTile;
      if (lt.onTap != null) {
        type = 'listTile';
        tappable = true;
        actions = ['tap'];
      }
    } else if (widget is BottomNavigationBar) {
      type = 'tabBar';
      actions = ['selectTab'];
    } else if (widget is TabBar) {
      type = 'tabBar';
      actions = ['selectTab'];
    }

    // Only emit if we have an ID or it's interactive
    if (id == null && !tappable) return null;

    final resolvedId = id ?? label ?? '${widget.runtimeType}_${frame.hashCode}';

    return {
      'id': resolvedId,
      'type': type,
      'label': label ?? '',
      'value': value ?? '',
      'enabled': true,
      'visible': true,
      'tappable': tappable,
      'frame': frame,
      'actions': actions,
    };
  }

  String? _getFrame(Element element) {
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

  void _dumpElement(Element element, int depth, int maxDepth, List<Map<String, dynamic>> nodes, Set<Element> visited) {
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

    final frame = _getFrame(element);
    if (frame != null) node['frame'] = frame;

    // Widget-specific properties
    if (widget is Text) {
      node['text'] = (widget as Text).data ?? '';
    } else if (widget is TextField) {
      final tf = widget as TextField;
      if (tf.decoration?.hintText != null) node['placeholder'] = tf.decoration!.hintText;
      if (tf.decoration?.labelText != null) node['label'] = tf.decoration!.labelText;
    } else if (widget is ElevatedButton || widget is TextButton || widget is OutlinedButton) {
      // button — child content described separately in tree
    } else if (widget is Checkbox) {
      node['checked'] = (widget as Checkbox).value?.toString();
    } else if (widget is Switch) {
      node['value'] = (widget as Switch).value.toString();
    } else if (widget is Semantics) {
      final props = (widget as Semantics).properties;
      if (props.label != null) node['semanticLabel'] = props.label;
    }

    nodes.add(node);
    element.visitChildren((child) => _dumpElement(child, depth + 1, maxDepth, nodes, visited));
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
