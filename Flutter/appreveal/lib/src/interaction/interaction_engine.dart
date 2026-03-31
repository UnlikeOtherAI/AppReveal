// All native Flutter interaction dispatch — taps, text, scroll, navigation.

import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '../elements/element_inventory.dart';
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

  Future<void> tap({required String elementId}) async {
    final element = ElementInventory.shared.findElement(elementId);
    if (element == null) throw Exception('Element not found: $elementId');
    final center = _centerOf(element);
    if (center == null) throw Exception('Cannot determine position of: $elementId');
    await _injectTap(center);
  }

  Future<void> tapPoint({required double x, required double y}) async {
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
    if (elementId != null) {
      // Find and tap the text field to focus it
      final element = ElementInventory.shared.findElement(elementId);
      if (element != null) {
        final center = _centerOf(element);
        if (center != null) {
          await _injectTap(center);
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
      }
    }

    // Find the focused EditableText and update its controller
    final editableState = _findFocusedEditableText();
    if (editableState == null) throw Exception('No focused text field found');

    final controller = editableState.widget.controller;
    final current = controller.text;
    final sel = controller.selection;
    final insertAt = sel.isValid ? sel.end : current.length;
    final newText = current.substring(0, insertAt) + text + current.substring(insertAt);
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: insertAt + text.length),
    );
  }

  Future<void> clearText({required String elementId}) async {
    final element = ElementInventory.shared.findElement(elementId);
    if (element == null) throw Exception('Element not found: $elementId');

    // Try to find EditableTextState in subtree
    EditableTextState? state;
    _visitElements(element, (el) {
      if (state != null) return false;
      if (el is StatefulElement && el.state is EditableTextState) {
        state = el.state as EditableTextState;
        return false;
      }
      return true;
    });

    if (state == null) {
      // Tap to focus then find
      final center = _centerOf(element);
      if (center != null) {
        await _injectTap(center);
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      state = _findFocusedEditableText();
    }

    if (state == null) throw Exception('No text field found for: $elementId');
    state!.widget.controller.value = const TextEditingValue(
      text: '',
      selection: TextSelection.collapsed(offset: 0),
    );
  }

  // ─── Scroll ──────────────────────────────────────────────────────────────

  Future<void> scroll({required String direction, String? containerId}) async {
    final root = WidgetsBinding.instance.renderViewElement;
    if (root == null) throw Exception('No root element');

    final scrollState = _findScrollableState(root, containerId);
    if (scrollState == null) throw Exception('No scrollable container found');

    final position = scrollState.position;
    const delta = 300.0;

    final target = switch (direction) {
      'down' => position.pixels + delta,
      'up' => position.pixels - delta,
      'right' => position.pixels + delta,
      'left' => position.pixels - delta,
      _ => throw Exception('Invalid direction: $direction'),
    };

    await position.animateTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> scrollToElement({required String elementId}) async {
    final element = ElementInventory.shared.findElement(elementId);
    if (element == null) throw Exception('Element not found: $elementId');
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
    navigator.pop();
    await _waitForFrame();
  }

  Future<void> dismissModal() async {
    // In Flutter, dismissing a modal is the same as popping the route
    await navigateBack();
  }

  Future<void> selectTab({required int index}) async {
    final root = WidgetsBinding.instance.renderViewElement;
    if (root == null) throw Exception('No root element');

    // Find BottomNavigationBar
    Element? tabBarElement;
    _visitElements(root, (el) {
      if (tabBarElement != null) return false;
      if (el.widget is BottomNavigationBar || el.widget is NavigationBar) {
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
          itemCount = (tabBarElement!.widget as BottomNavigationBar).items.length;
        } else if (tabBarElement!.widget is NavigationBar) {
          itemCount = (tabBarElement!.widget as NavigationBar).destinations.length;
        }
        if (index >= itemCount) throw Exception('Tab index $index out of range (0-${itemCount - 1})');
        final offset = renderBox.localToGlobal(Offset.zero);
        final itemWidth = size.width / itemCount;
        final tapX = offset.dx + itemWidth * index + itemWidth / 2;
        final tapY = offset.dy + size.height / 2;
        await _injectTap(Offset(tapX, tapY));
        return;
      }
    }

    // Try TabBar
    Element? flutterTabBar;
    _visitElements(root, (el) {
      if (flutterTabBar != null) return false;
      if (el.widget is TabBar) {
        flutterTabBar = el;
        return false;
      }
      return true;
    });

    if (flutterTabBar != null) {
      final renderBox = flutterTabBar!.renderObject as RenderBox?;
      if (renderBox != null && renderBox.attached) {
        final size = renderBox.size;
        final tabs = (flutterTabBar!.widget as TabBar).tabs;
        if (index >= tabs.length) throw Exception('Tab index $index out of range (0-${tabs.length - 1})');
        final offset = renderBox.localToGlobal(Offset.zero);
        final itemWidth = size.width / tabs.length;
        final tapX = offset.dx + itemWidth * index + itemWidth / 2;
        final tapY = offset.dy + size.height / 2;
        await _injectTap(Offset(tapX, tapY));
        return;
      }
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

  Offset? _centerOf(Element element) {
    try {
      final renderObject = element.renderObject;
      if (renderObject is! RenderBox) return null;
      if (!renderObject.attached) return null;
      final size = renderObject.size;
      return renderObject.localToGlobal(Offset(size.width / 2, size.height / 2));
    } catch (_) {
      return null;
    }
  }

  EditableTextState? _findFocusedEditableText() {
    final root = WidgetsBinding.instance.renderViewElement;
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

  ScrollableState? _findScrollableState(Element root, String? containerId) {
    ScrollableState? found;
    ElementInventory.visitAll(root, (element) {
      if (found != null) return false;
      if (element is StatefulElement && element.state is ScrollableState) {
        if (containerId == null) {
          found = element.state as ScrollableState;
          return false;
        }
        final key = element.widget.key;
        if (key is ValueKey<String> && key.value == containerId) {
          found = element.state as ScrollableState;
          return false;
        }
      }
      return true;
    });
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
