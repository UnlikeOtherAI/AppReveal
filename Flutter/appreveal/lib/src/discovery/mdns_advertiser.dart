// mDNS service advertisement via the nsd package.

import 'dart:convert';
import 'dart:typed_data';
import 'package:nsd/nsd.dart';

class MdnsAdvertiser {
  static final shared = MdnsAdvertiser._();
  MdnsAdvertiser._();

  Registration? _registration;

  Future<void> register({
    required int port,
    required String bundleId,
    required String version,
  }) async {
    try {
      _registration = await startRegistration(
        Service(
          name: 'AppReveal-$bundleId',
          type: '_appreveal._tcp.',
          port: port,
          txt: {
            'bundleId': Uint8List.fromList(utf8.encode(bundleId)),
            'version': Uint8List.fromList(utf8.encode(version)),
            'transport': Uint8List.fromList(utf8.encode('streamable-http')),
          },
        ),
      );
    } catch (e) {
      // mDNS failure is non-fatal — server still works via direct IP
      // ignore: avoid_print
      print('[AppReveal] mDNS registration failed: $e');
    }
  }

  Future<void> unregister() async {
    final reg = _registration;
    if (reg != null) {
      await stopRegistration(reg);
      _registration = null;
    }
  }
}
