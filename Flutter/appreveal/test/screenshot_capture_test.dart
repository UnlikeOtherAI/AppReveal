import 'dart:convert';
import 'dart:typed_data';

import 'package:appreveal/src/screenshot/screenshot_capture.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
