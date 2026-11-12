// Screen and element screenshot capture.

import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;

import '../elements/element_inventory.dart';
import '../elements/element_resolver.dart';

class ScreenshotCapture {
  static final shared = ScreenshotCapture._();
  ScreenshotCapture._();

  /// Optional explicit repaint boundary key, set via [AppReveal.wrap].
  static final screenshotKey = GlobalKey();

  @visibleForTesting
  static Uint8List encodeImageBytes({
    required ByteData byteData,
    required int width,
    required int height,
    required String format,
  }) {
    if (format != 'jpeg') {
      return byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
    }

    return img.encodeJpg(
      img.Image.fromBytes(
        width: width,
        height: height,
        bytes: byteData.buffer,
        bytesOffset: byteData.offsetInBytes,
        numChannels: 4,
        rowStride: width * 4,
        order: img.ChannelOrder.rgba,
      ),
      quality: 85,
    );
  }

  Future<Map<String, dynamic>> captureScreen({String format = 'png'}) async {
    // Try the explicit key first
    RenderRepaintBoundary? boundary = _boundaryFromKey();
    // Fall back to finding the first repaint boundary in the tree
    boundary ??= _findRepaintBoundary(
      RendererBinding.instance.rootPipelineOwner.rootNode,
    );
    if (boundary == null) {
      return {
        'error':
            'No repaint boundary found. Wrap your app with AppReveal.wrap(MyApp())'
      };
    }
    return _capture(boundary, format: format);
  }

  Future<Map<String, dynamic>> captureElement({
    required String elementId,
    String format = 'png',
  }) async {
    final target = ElementResolver.shared.resolve(elementId);
    if (target == null) return {'error': 'Element not found: $elementId'};
    if (ElementInventory.visibleRect(target) == null) {
      return {'error': 'Element is not visible: $elementId'};
    }
    final renderObject = target.renderObject;
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return {'error': 'Element has no render box'};
    }
    RenderObject? ancestor = renderObject;
    while (ancestor != null && ancestor is! RenderRepaintBoundary) {
      ancestor = ancestor.parent;
    }
    if (ancestor is! RenderRepaintBoundary) {
      return {
        'error':
            'No repaint boundary for element. Wrap your app with AppReveal.wrap.'
      };
    }
    final rect = MatrixUtils.transformRect(
        renderObject.getTransformTo(ancestor), Offset.zero & renderObject.size);
    return _capture(ancestor, format: format, region: rect);
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
      found ??= _findRepaintBoundary(child);
    });
    return found;
  }

  Future<Map<String, dynamic>> _capture(
    RenderRepaintBoundary boundary, {
    required String format,
    Rect? region,
  }) async {
    final normalizedFormat = format == 'jpeg' ? 'jpeg' : 'png';
    try {
      if (boundary.debugNeedsPaint) await WidgetsBinding.instance.endOfFrame;
      final bounds = (region ?? (Offset.zero & boundary.size))
          .intersect(Offset.zero & boundary.size);
      if (bounds.isEmpty) {
        return {'error': 'Screenshot target is outside the painted boundary'};
      }
      var image = await boundary.toImage(pixelRatio: 2.0);
      if (region != null) {
        final fullImage = image;
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        final width = (bounds.width * 2).ceil();
        final height = (bounds.height * 2).ceil();
        canvas.drawImageRect(
            fullImage,
            Rect.fromLTWH(bounds.left * 2, bounds.top * 2, bounds.width * 2,
                bounds.height * 2),
            Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
            Paint());
        final picture = recorder.endRecording();
        try {
          image = await picture.toImage(width, height);
        } finally {
          picture.dispose();
          fullImage.dispose();
        }
      }
      try {
        final byteData = await image.toByteData(
          format: normalizedFormat == 'jpeg'
              ? ui.ImageByteFormat.rawRgba
              : ui.ImageByteFormat.png,
        );
        if (byteData == null) return {'error': 'Failed to encode image'};

        final encodedBytes = encodeImageBytes(
          byteData: byteData,
          width: image.width,
          height: image.height,
          format: normalizedFormat,
        );

        return {
          'image': base64Encode(encodedBytes),
          'width': image.width,
          'height': image.height,
          'scale': 2.0,
          'format': normalizedFormat,
        };
      } finally {
        image.dispose();
      }
    } catch (e) {
      return {'error': e.toString()};
    }
  }
}
