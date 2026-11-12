// All native Flutter interaction dispatch — taps, text, scroll, navigation.

import 'dart:async';

import 'package:flutter/gestures.dart';
// Retain compatibility with Flutter versions before the UI package split.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/rendering.dart';
import 'package:url_launcher/url_launcher.dart';

import '../elements/element_inventory.dart';
import '../elements/element_resolver.dart';
import '../screen/navigator_observer.dart';

class InteractionEngine {
  static final shared = InteractionEngine._();
  InteractionEngine._();

  AppRevealNavigatorObserver? _observer;
  int _pointerCounter = 1;

  void attachObserver(AppRevealNavigatorObserver observer) {
    _observer = observer;
  }

  // ─── Tap ─────────────────────────────────────────────────────────────────

  /// Tap an element resolved by ID with enhanced fallback matching.
  Future<void> tap({required String elementId}) async {
    final element = ElementResolver.shared.resolve(elementId);
    if (element == null) {
      throw Exception(
        'Element "$elementId" not found. '
        'Use get_elements to list available IDs, or tap_text to target by visible text.',
      );
    }
    await tapElement(element);
  }

  /// Tap a pre-resolved Element directly.
  Future<void> tapElement(Element element) async {
    final rect = ElementInventory.visibleRect(element);
    if (rect == null) {
      throw Exception('Target is not visible. Use scroll_to_element first.');
    }
    final widget = element.widget;
    final enabled = switch (widget) {
      ButtonStyleButton() => widget.onPressed != null,
      IconButton() => widget.onPressed != null,
      FloatingActionButton() => widget.onPressed != null,
      TextField() => widget.enabled != false,
      TextFormField() => widget.enabled,
      ListTile() => widget.enabled,
      Checkbox() => widget.onChanged != null,
      Switch() => widget.onChanged != null,
      CheckboxListTile() => widget.onChanged != null,
      SwitchListTile() => widget.onChanged != null,
      DropdownButton() => widget.onChanged != null,
      PopupMenuButton() => widget.enabled,
      _ => true,
    };
    if (!enabled) throw Exception('Target is disabled');
    final renderObject = element.renderObject;
    final hit = HitTestResult();
    WidgetsBinding.instance.hitTestInView(hit, rect.center,
        WidgetsBinding.instance.platformDispatcher.views.first.viewId);
    final reachable = hit.path.any((entry) {
      var target = entry.target;
      while (target is RenderObject) {
        if (identical(target, renderObject)) return true;
        final parent = target.parent;
        if (parent == null) break;
        target = parent;
      }
      return false;
    });
    if (!reachable) {
      throw Exception('Target is obscured or does not receive pointer events');
    }
    await _injectTap(rect.center);
  }

  Future<void> tapPoint({required double x, required double y}) async {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final bounds = Offset.zero & (view.physicalSize / view.devicePixelRatio);
    if (!x.isFinite || !y.isFinite || !bounds.contains(Offset(x, y))) {
      throw ArgumentError(
          'Coordinates must be inside the logical screen bounds');
    }
    await _injectTap(Offset(x, y));
  }

  Future<void> _injectTap(Offset position) async {
    final pointer = _pointerCounter++;
    final now = Duration(microseconds: DateTime.now().microsecondsSinceEpoch);

    WidgetsBinding.instance.handlePointerEvent(PointerDownEvent(
      timeStamp: now,
      pointer: pointer,
      position: position,
      kind: PointerDeviceKind.touch,
    ));

    await Future<void>.delayed(const Duration(milliseconds: 50));

    WidgetsBinding.instance.handlePointerEvent(PointerUpEvent(
      timeStamp: now + const Duration(milliseconds: 50),
      pointer: pointer,
      position: position,
      kind: PointerDeviceKind.touch,
    ));

    // Allow a frame to process
    await _waitForFrame();
  }

  // ─── Text Input ──────────────────────────────────────────────────────────

  Future<void> typeText({required String text, String? elementId}) async {
    final state = await _editableTarget(elementId);
    final current = state.widget.controller.value;
    final selection = current.selection.isValid
        ? current.selection
        : TextSelection.collapsed(offset: current.text.length);
    final newText =
        current.text.replaceRange(selection.start, selection.end, text);
    state.userUpdateTextEditingValue(
      TextEditingValue(
          text: newText,
          selection:
              TextSelection.collapsed(offset: selection.start + text.length)),
      SelectionChangedCause.keyboard,
    );
    await _waitForFrame();
  }

  Future<void> clearText({required String elementId}) async {
    final state = await _editableTarget(elementId);
    state.userUpdateTextEditingValue(
      const TextEditingValue(
          text: '', selection: TextSelection.collapsed(offset: 0)),
      SelectionChangedCause.keyboard,
    );
    await _waitForFrame();
  }

  Future<EditableTextState> _editableTarget(String? id) async {
    EditableTextState? state;
    if (id != null) {
      final element = ElementResolver.shared.resolve(id);
      if (element == null) throw Exception('Element not found: $id');
      ElementInventory.visitAll(element, (child) {
        if (child is StatefulElement && child.state is EditableTextState) {
          state = child.state as EditableTextState;
          return false;
        }
        return true;
      });
      if (state == null) throw Exception('Element is not a text field: $id');
      if (state!.widget.readOnly || !state!.widget.focusNode.canRequestFocus) {
        throw Exception('Text field is read-only or disabled: $id');
      }
      if (!state!.widget.focusNode.hasFocus) await tapElement(element);
      if (!state!.widget.focusNode.hasFocus) {
        throw Exception('Could not focus text field: $id');
      }
    } else {
      state = _findFocusedEditableText();
    }
    if (state == null) throw Exception('No focused text field found');
    if (state!.widget.readOnly ||
        !ElementInventory.isActive(state!.context as Element)) {
      throw Exception('Text field is read-only or inactive');
    }
    return state!;
  }

  // ─── Scroll ──────────────────────────────────────────────────────────────

  Future<void> scroll({required String direction, String? containerId}) async {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) throw Exception('No root element');

    final scrollState = _findScrollableState(root, containerId, direction);
    if (scrollState == null) throw Exception('No scrollable container found');

    final position = scrollState.position;
    const delta = 300.0;

    final axis = axisDirectionToAxis(position.axisDirection);
    final requestedAxis = (direction == 'up' || direction == 'down')
        ? Axis.vertical
        : Axis.horizontal;
    if (!['up', 'down', 'left', 'right'].contains(direction) ||
        axis != requestedAxis) {
      throw ArgumentError(
          'Direction $direction does not match the scroll axis');
    }
    if (!position.physics.shouldAcceptUserOffset(position)) {
      throw Exception('Container does not allow scrolling');
    }
    final forward = direction == 'down' || direction == 'right';
    final reversed = position.axisDirection == AxisDirection.up ||
        position.axisDirection == AxisDirection.left;
    final target = position.pixels + (forward != reversed ? delta : -delta);

    await position.animateTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> scrollToElement({required String elementId}) async {
    final element = ElementResolver.shared.resolve(elementId);
    if (element == null) {
      throw Exception(
        'Element "$elementId" not found. '
        'Use get_elements to list available IDs.',
      );
    }
    await Scrollable.ensureVisible(
      element,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  // ─── Navigation ──────────────────────────────────────────────────────────

  Future<void> navigateBack() async {
    final navigator = _observer?.navigator;
    if (navigator == null || !navigator.canPop()) {
      throw Exception('Cannot go back — no route to pop');
    }
    final route = _observer?.currentRouteObject;
    final localHistory = route?.willHandlePopInternally ?? false;
    final handled = await navigator.maybePop();
    await _waitForFrame();
    if (!handled ||
        (!localHistory &&
            identical(route, _observer?.currentRouteObject) &&
            route?.isCurrent == true)) {
      throw Exception('Navigation was blocked by the current route');
    }
  }

  Future<void> dismissModal() async {
    if (_observer?.currentRouteObject is! PopupRoute) {
      throw Exception('No modal or dialog is presented');
    }
    await navigateBack();
  }

  Future<void> selectTab({required int index}) async {
    if (index < 0) throw ArgumentError('Tab index must be non-negative');
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) throw Exception('No root element');

    // Find BottomNavigationBar
    Element? tabBarElement;
    _visitElements(root, (el) {
      if (tabBarElement != null) return false;
      if (ElementInventory.visibleRect(el) != null &&
          (el.widget is BottomNavigationBar || el.widget is NavigationBar)) {
        tabBarElement = el;
        return false;
      }
      return true;
    });

    if (tabBarElement != null) {
      final renderBox = tabBarElement!.renderObject as RenderBox?;
      if (renderBox != null && renderBox.attached) {
        final size = renderBox.size;
        // Get the number of items
        int itemCount = 2;
        if (tabBarElement!.widget is BottomNavigationBar) {
          itemCount =
              (tabBarElement!.widget as BottomNavigationBar).items.length;
        } else if (tabBarElement!.widget is NavigationBar) {
          itemCount =
              (tabBarElement!.widget as NavigationBar).destinations.length;
        }
        if (index >= itemCount) {
          throw Exception('Tab index $index out of range (0-${itemCount - 1})');
        }
        final offset = renderBox.localToGlobal(Offset.zero);
        final itemWidth = size.width / itemCount;
        final rtl = tabBarElement!
                .getInheritedWidgetOfExactType<Directionality>()
                ?.textDirection ==
            TextDirection.rtl;
        final visualIndex = rtl ? itemCount - 1 - index : index;
        final tapX = offset.dx + itemWidth * visualIndex + itemWidth / 2;
        final padding = tabBarElement!
                .getInheritedWidgetOfExactType<MediaQuery>()
                ?.data
                .padding
                .bottom ??
            0;
        final tapY = offset.dy + (size.height - padding) / 2;
        await _injectTap(Offset(tapX, tapY));
        return;
      }
    }

    // Try TabBar
    Element? flutterTabBar;
    _visitElements(root, (el) {
      if (flutterTabBar != null) return false;
      if (el.widget is TabBar && ElementInventory.visibleRect(el) != null) {
        flutterTabBar = el;
        return false;
      }
      return true;
    });

    if (flutterTabBar != null) {
      final bar = flutterTabBar!.widget as TabBar;
      if (index >= bar.tabs.length) {
        throw ArgumentError('Tab index $index out of range');
      }
      Element? target;
      ElementInventory.visitAll(flutterTabBar!, (element) {
        if (identical(element.widget, bar.tabs[index])) {
          target = element;
          return false;
        }
        return true;
      });
      if (target == null) throw Exception('Tab is not rendered');
      await Scrollable.ensureVisible(target!);
      await _waitForFrame();
      await tapElement(target!);
      return;
    }

    throw Exception('No tab bar found');
  }

  Future<void> openDeeplink({required String url}) async {
    final uri = Uri.tryParse(url);
    if (uri == null) throw Exception('Invalid URL: $url');
    if (!await launchUrl(uri)) {
      throw Exception('Could not open URL: $url');
    }
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  EditableTextState? _findFocusedEditableText() {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return null;
    EditableTextState? found;
    _visitElements(root, (el) {
      if (found != null) return false;
      if (el is StatefulElement && el.state is EditableTextState) {
        final state = el.state as EditableTextState;
        if (state.widget.focusNode.hasFocus) {
          found = state;
          return false;
        }
      }
      return true;
    });
    return found;
  }

  ScrollableState? _findScrollableState(
      Element root, String? containerId, String direction) {
    if (containerId == null) {
      // Find first ScrollableState
      ScrollableState? found;
      ElementInventory.visitAll(root, (element) {
        if (found != null) return false;
        if (element is StatefulElement && element.state is ScrollableState) {
          final candidate = element.state as ScrollableState;
          final axis = (direction == 'up' || direction == 'down')
              ? Axis.vertical
              : Axis.horizontal;
          if (ElementInventory.visibleRect(element) != null &&
              axisDirectionToAxis(candidate.position.axisDirection) == axis &&
              candidate.position.maxScrollExtent >
                  candidate.position.minScrollExtent) {
            found = candidate;
            return false;
          }
        }
        return true;
      });
      return found;
    }

    // Try exact key match on ScrollableState first (backward compat)
    ScrollableState? found;
    ElementInventory.visitAll(root, (element) {
      if (found != null) return false;
      if (element is StatefulElement && element.state is ScrollableState) {
        final key = element.widget.key;
        if (key is ValueKey<String> && key.value == containerId) {
          found = element.state as ScrollableState;
          return false;
        }
      }
      return true;
    });
    if (found != null) return found;

    // Enhanced: resolve container by ID, then find ScrollableState inside
    final container = ElementResolver.shared.resolve(containerId);
    if (container != null) {
      ElementInventory.visitAll(container, (element) {
        if (found != null) return false;
        if (element is StatefulElement && element.state is ScrollableState) {
          found = element.state as ScrollableState;
          return false;
        }
        return true;
      });
    }

    return found;
  }

  void _visitElements(Element element, bool Function(Element) visitor) {
    ElementInventory.visitAll(element, visitor);
  }

  Future<void> _waitForFrame() async {
    final completer = Completer<void>();
    SchedulerBinding.instance.addPostFrameCallback((_) => completer.complete());
    SchedulerBinding.instance.scheduleFrame();
    await completer.future;
  }
}
