// Flutter widget tree inspection — element listing and full tree dump.

import 'dart:math' as math;

// Retain compatibility with Flutter versions before the UI package split.
// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart';
// Retain compatibility with Flutter versions before the UI package split.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

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
  List<Map<String, dynamic>> listElements() => _inventory().$1;

  (List<Map<String, dynamic>>, Map<String, Element>) _inventory() {
    final results = <Map<String, dynamic>>[];
    final targets = <String, Element>{};
    final root = WidgetsBinding.instance.rootElement;
    if (root != null) {
      _collectElements(root, results, <String>{}, <Element>{}, targets);
    }
    return (results, targets);
  }

  /// Full widget tree dump for get_view_tree.
  List<Map<String, dynamic>> dumpWidgetTree({int maxDepth = 50}) {
    final root = WidgetsBinding.instance.rootElement;
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
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return null;
    final listed = _inventory().$2[id];
    if (listed != null) return listed;

    // Keep keyed, laid-out offscreen children available to scroll_to_element.
    Element? found;
    void walk(Element element) {
      if (found != null || !isActive(element)) return;
      final key = element.widget.key;
      final widget = element.widget;
      if ((key is ValueKey<String> && key.value == id) ||
          (widget is Semantics && widget.properties.label == id)) {
        found = element;
        return;
      }
      element.visitChildren(walk);
    }

    walk(root);
    return found;
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
    final rect = getFrameRect(element);
    if (rect == null) return null;
    return '${rect.left.round()},${rect.top.round()},${rect.width.round()},${rect.height.round()}';
  }

  static Rect? getFrameRect(Element element) {
    try {
      final renderObject = element.renderObject;
      if (renderObject is! RenderBox) return null;
      if (!renderObject.attached) return null;
      if (!renderObject.hasSize || renderObject.size.isEmpty) return null;
      final rect = MatrixUtils.transformRect(
          renderObject.getTransformTo(null), Offset.zero & renderObject.size);
      return rect.isFinite && !rect.isEmpty ? rect : null;
    } catch (_) {
      return null;
    }
  }

  /// Exclude retained routes, inactive tabs and fully transparent subtrees.
  /// These are non-subscribing reads, including when called outside build.
  static bool isActive(Element element) {
    if (!element.mounted) return false;
    bool active = true;
    final branch = <Widget>{element.widget};
    bool inspect(Element candidate) {
      final widget = candidate.widget;
      if ((widget is Offstage && widget.offstage) ||
          (widget is Visibility && !widget.visible) ||
          (widget is Opacity && widget.opacity == 0)) {
        active = false;
      }
      if (candidate != element &&
          widget is IndexedStack &&
          (widget.index == null ||
              (widget.children.any(branch.contains) &&
                  !branch.contains(widget.children[widget.index!])))) {
        active = false;
      }
      branch.add(widget);
      return active;
    }

    inspect(element);
    if (active) element.visitAncestorElements(inspect);
    return active;
  }

  static Rect? visibleRect(Element element) {
    if (!isActive(element)) return null;
    var rect = getFrameRect(element);
    if (rect == null) return null;
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    rect = rect
        .intersect(Offset.zero & (view.physicalSize / view.devicePixelRatio));
    RenderObject? child = element.renderObject;
    while (child != null && child.parent is RenderObject) {
      final parent = child.parent!;
      final clip = parent.describeApproximatePaintClip(child);
      if (clip != null) {
        rect = rect!.intersect(
            MatrixUtils.transformRect(parent.getTransformTo(null), clip));
      }
      child = parent;
    }
    return rect!.isEmpty ? null : rect;
  }

  // Inspection runs from an MCP request, outside any build, against elements
  // the host app owns. It must READ inherited values, never subscribe to them:
  // `MediaQuery.maybeOf` / `Directionality.maybeOf` are
  // `dependOnInheritedWidgetOfExactType` lookups and would register the
  // inspected element as a dependent. On a MediaQuery element that makes it its
  // own dependent, so the next MediaQuery update fails
  // `InheritedElement.notifyClients` and leaves the host's tree corrupt
  // (`_dependents.isEmpty`, error screen). `getInheritedWidgetOfExactType`
  // resolves the same widget without registering anything.
  static MediaQueryData? _mediaQueryOf(Element element) =>
      element.getInheritedWidgetOfExactType<MediaQuery>()?.data;

  static TextDirection? _textDirectionOf(Element element) =>
      element.getInheritedWidgetOfExactType<Directionality>()?.textDirection;

  static Map<String, double> getSafeAreaInsets(Element element) {
    final mediaQuery = _mediaQueryOf(element);
    if (mediaQuery == null) {
      return {'top': 0, 'leading': 0, 'bottom': 0, 'trailing': 0};
    }

    final textDirection = _textDirectionOf(element) ?? TextDirection.ltr;
    final padding = mediaQuery.padding;
    final isRtl = textDirection == TextDirection.rtl;

    return {
      'top': padding.top,
      'leading': isRtl ? padding.right : padding.left,
      'bottom': padding.bottom,
      'trailing': isRtl ? padding.left : padding.right,
    };
  }

  static Map<String, double>? getSafeAreaLayoutGuideFrame(Element element) {
    final frameRect = getFrameRect(element);
    if (frameRect == null) return null;

    final mediaQuery = _mediaQueryOf(element);
    if (mediaQuery == null) {
      return {
        'x': frameRect.left,
        'y': frameRect.top,
        'width': frameRect.width,
        'height': frameRect.height,
      };
    }

    final padding = mediaQuery.padding;
    final safeRect = Rect.fromLTRB(
      padding.left,
      padding.top,
      mediaQuery.size.width - padding.right,
      mediaQuery.size.height - padding.bottom,
    );
    final intersection = safeRect.intersect(frameRect);
    final x = math.max(frameRect.left, safeRect.left);
    final y = math.max(frameRect.top, safeRect.top);
    final width = math.max(0.0, intersection.width);
    final height = math.max(0.0, intersection.height);

    return {'x': x, 'y': y, 'width': width, 'height': height};
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
    if (widget is Text) return widget.data ?? widget.textSpan?.toPlainText();
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
    Map<String, Element> targets,
  ) {
    if (!visited.add(element) || !isActive(element)) return;

    final info = _describeInteractive(element);
    if (info != null) {
      // Skip raw tappables (InkWell/GestureDetector) that live inside a
      // logical tappable parent — the parent is already surfaced.
      if (info['type'] == 'tappable' &&
          info['idSource'] != 'explicit' &&
          _hasLogicalTappableAncestor(element)) {
        element.visitChildren(
          (child) => _collectElements(child, results, seen, visited, targets),
        );
        return;
      }

      final id = _dedupeListedId(info['id'] as String, seen);
      info['id'] = id;
      targets[id] = element;
      results.add(info);
    }

    // Standalone Semantics nodes
    final widget = element.widget;
    if (widget is Semantics) {
      final label = widget.properties.label;
      if (label != null && label.isNotEmpty && !seen.contains(label)) {
        final frame = getFrame(element);
        if (frame != null && visibleRect(element) != null) {
          final safeAreaLayoutGuideFrame = getSafeAreaLayoutGuideFrame(element);
          seen.add(label);
          targets[label] = element;
          results.add({
            'id': label,
            'type': 'semantic',
            'label': label,
            'value': widget.properties.value ?? '',
            'enabled': !(widget.properties.enabled == false),
            'visible': true,
            'tappable': widget.properties.onTap != null,
            'frame': frame,
            'safeAreaInsets': getSafeAreaInsets(element),
            'safeAreaLayoutGuideFrame': safeAreaLayoutGuideFrame,
            'actions': widget.properties.onTap != null ? ['tap'] : [],
            'idSource': 'semantics',
          });
        }
      }
    }

    element.visitChildren(
      (child) => _collectElements(child, results, seen, visited, targets),
    );
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
    if (frame == null || visibleRect(element) == null) return null;

    String? explicitId;
    String type = 'view';
    bool tappable = false;
    bool enabled = true;
    String? label;
    String? value;
    List<String> actions = [];
    String idSource = 'derived';
    final safeAreaInsets = getSafeAreaInsets(element);
    final safeAreaLayoutGuideFrame = getSafeAreaLayoutGuideFrame(element);

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
      enabled = widget.enabled ?? true;
      value = widget.obscureText ? '' : widget.controller?.text;
      actions = widget.readOnly ? ['tap'] : ['tap', 'type', 'clear'];
    } else if (widget is TextFormField) {
      type = 'textField';
      tappable = true;
      enabled = widget.enabled;
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
      // ignore: deprecated_member_use
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
    } else if (_isSegmentedControl(widget)) {
      type = 'segmentedControl';
      tappable = true;
      actions = ['tap'];
      label = extractFirstText(element);
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
      'safeAreaInsets': safeAreaInsets,
      'safeAreaLayoutGuideFrame': safeAreaLayoutGuideFrame,
      'actions': actions,
      'idSource': idSource,
    };
  }

  void _dumpElement(
    Element element,
    int depth,
    int maxDepth,
    List<Map<String, dynamic>> nodes,
    Set<Element> visited,
  ) {
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
    node['safeAreaInsets'] = getSafeAreaInsets(element);
    final safeAreaLayoutGuideFrame = getSafeAreaLayoutGuideFrame(element);
    if (safeAreaLayoutGuideFrame != null) {
      node['safeAreaLayoutGuideFrame'] = safeAreaLayoutGuideFrame;
    }

    // Widget-specific properties
    if (widget is Text) {
      node['text'] = widget.data ?? widget.textSpan?.toPlainText() ?? '';
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
      (child) => _dumpElement(child, depth + 1, maxDepth, nodes, visited),
    );
  }

  static bool _isSegmentedControl(Widget widget) {
    final typeName = widget.runtimeType.toString();
    return widget is CupertinoSegmentedControl ||
        widget is CupertinoSlidingSegmentedControl ||
        widget is SegmentedButton ||
        widget is ToggleButtons ||
        typeName.contains('SegmentedControl') ||
        typeName.contains('SegmentedButton');
  }

  String _dedupeListedId(String id, Set<String> seen) {
    if (seen.add(id)) return id;

    var index = 1;
    while (!seen.add('${id}_$index')) {
      index++;
    }
    return '${id}_$index';
  }
}
