import 'dart:convert';
import 'dart:typed_data';

import 'package:appreveal/src/screenshot/screenshot_capture.dart';
import 'package:flutter_test/flutter_test.dart';
// Retain compatibility with Flutter versions before the UI package split.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

void main() {
  testWidgets('element capture crops ordinary keyed and derived widgets',
      (tester) async {
    await tester.pumpWidget(RepaintBoundary(
      key: ScreenshotCapture.screenshotKey,
      child: MaterialApp(
          home: Scaffold(
              body: Column(children: [
        const SizedBox(
            key: ValueKey('red'),
            width: 40,
            height: 30,
            child: ColoredBox(color: Colors.red)),
        ElevatedButton(onPressed: () {}, child: const Text('Capture me')),
      ]))),
    ));
    await tester.pumpAndSettle();
    // Image encoding runs on the real engine, outside the fake test clock.
    final result = await tester.runAsync(
        () => ScreenshotCapture.shared.captureElement(elementId: 'red'));
    expect(result, isNot(contains('error')));
    expect(result!['width'], 80);
    expect(result['height'], 60);
    final image = img.decodePng(base64Decode(result['image'] as String))!;
    expect(
        image.getPixel(20, 20).r, 244); // Material red, not surrounding white.
    final derived = await tester.runAsync(() => ScreenshotCapture.shared
        .captureElement(elementId: 'capture_me', format: 'jpeg'));
    expect(derived, isNot(contains('error')));
    expect(img.decodeJpg(base64Decode(derived!['image'] as String)), isNotNull);
    final missing =
        await ScreenshotCapture.shared.captureElement(elementId: 'absent');
    expect(missing, contains('error'));
  });

  test('JPEG encoder returns valid JPEG bytes', () {
    final rgba = Uint8List.fromList([
      255,
      0,
      0,
      255,
      0,
      255,
      0,
      255,
      0,
      0,
      255,
      255,
      255,
      255,
      255,
      255,
    ]);
    final bytes = ScreenshotCapture.encodeImageBytes(
      byteData: ByteData.sublistView(rgba),
      width: 2,
      height: 2,
      format: 'jpeg',
    );
    final decoded = base64Decode(base64Encode(bytes));

    expect(decoded.take(2), [0xFF, 0xD8]);
    expect(decoded.skip(decoded.length - 2), [0xFF, 0xD9]);
  });
}
