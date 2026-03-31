// Screen and element screenshot capture.

import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../elements/element_inventory.dart';

class ScreenshotCapture {
  static final shared = ScreenshotCapture._();
  ScreenshotCapture._();

  /// Optional explicit repaint boundary key, set via [AppReveal.wrap].
  static final screenshotKey = GlobalKey();

  Future<Map<String, dynamic>> captureScreen({String format = 'png'}) async {
    // Try the explicit key first
    RenderRepaintBoundary? boundary = _boundaryFromKey();
    // Fall back to finding the first repaint boundary in the tree
    boundary ??= _findRepaintBoundary(WidgetsBinding.instance.renderView);
    if (boundary == null) {
      return {'error': 'No repaint boundary found. Wrap your app with AppReveal.wrap(MyApp())'};
    }
    return _capture(boundary, format: format);
  }

  Future<Map<String, dynamic>> captureElement({
    required String elementId,
    String format = 'png',
  }) async {
    final root = WidgetsBinding.instance.renderViewElement;
    if (root == null) return {'error': 'No root element'};

    Element? target;
    _visitElements(root, (el) {
      if (target != null) return false;
      if (el.widget.key is ValueKey<String> &&
          (el.widget.key as ValueKey<String>).value == elementId) {
        target = el;
        return false;
      }
      return true;
    });

    if (target == null) return {'error': 'Element not found: $elementId'};

    final renderObject = target!.renderObject;
    if (renderObject is! RenderBox) return {'error': 'Element has no render box'};

    final boundary = _findRepaintBoundary(renderObject);
    if (boundary == null) return {'error': 'No repaint boundary for element'};

    return _capture(boundary, format: format);
  }

  RenderRepaintBoundary? _boundaryFromKey() {
    final context = screenshotKey.currentContext;
    if (context == null) return null;
    final renderObject = context.findRenderObject();
    if (renderObject is RenderRepaintBoundary) return renderObject;
    return null;
  }

  RenderRepaintBoundary? _findRepaintBoundary(RenderObject? obj) {
    if (obj == null) return null;
    if (obj is RenderRepaintBoundary) return obj;
    RenderRepaintBoundary? found;
    obj.visitChildren((child) {
      if (found == null) found = _findRepaintBoundary(child);
    });
    return found;
  }

  Future<Map<String, dynamic>> _capture(
    RenderRepaintBoundary boundary, {
    required String format,
  }) async {
    try {
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(
        format: format == 'jpeg' ? ui.ImageByteFormat.rawRgba : ui.ImageByteFormat.png,
      );
      if (byteData == null) return {'error': 'Failed to encode image'};
      final base64Image = base64Encode(byteData.buffer.asUint8List());
      return {
        'image': base64Image,
        'width': image.width,
        'height': image.height,
        'scale': 2.0,
        'format': format,
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  void _visitElements(Element element, bool Function(Element) visitor) {
    ElementInventory.visitAll(element, visitor);
  }
}
